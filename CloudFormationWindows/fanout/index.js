'use strict';

console.log('Loading function');
var http = require('http');
var https = require('https');
var AWS = require('aws-sdk');
var ipRangeCheck = require('ip-range-check');


// The code outside of the handler is executed just the once. Make sure it doesn't need to be dynamic.

// Errors are formatted for processing by the API Gateway so that a caller gets useful diagnostics.
// So notice that it doesn't call callback( err ) as the caller would end up with a 502 error and no message or stack trace.
// Thus all calls to this Lambda function are 'successful'. It requires the API Gateway to interpret the statusCode
// and return that to the caller as the HTTP response.
function returnAPIError( repository,  statusCode, message, callback, context) {
    // Construct an error object so that we can omit returnAPIError from the stack trace
    const myObject = {};
    Error.captureStackTrace(myObject, returnAPIError);

    let responseBody = {
        errorMessage: message + ' (using ' + context.invokedFunctionArn + ')',
        stackTrace: (myObject.stack)
    };
    console.log( "responseBody: ", responseBody);
    let response = {
        statusCode: statusCode,
        body: JSON.stringify(responseBody)
    };

    if ( repository.name ) {
        if ( repository.realDeployment) {
            postDashboardState(repository, "Deployment Failed", response, callback, context );
        } else {
            postDashboardState(repository, "Cloud Init Failed", response, callback, context );
        }
    } else {
        if (callback) {
            callback( null, response);
        }
    }

    return response;
}

function returnWarning( repository,  message, callback, context) {
    let responseBody = {
        errorMessage: repository.name + ' ' + message,
    };
    console.log( "responseBody: ", responseBody);

    // Send a response code to indicate its not been processed (202 = Accepted) and its probably not an error. e.g. webserver & gitdeployhub repos are not handled through here
    // This stops error being reported for repos that are not handled by this function, and at the same time a clear message is returned.
    let response = {
        statusCode: 202,
        body: JSON.stringify(responseBody)
    };
    if (callback) {
        callback( null, response);
    }
    return response;
}

function postDashboardState(repository, state, response, callback, context ) {
    let PublicIpAddress = 'paas.lansa.com.au';
    // console.log("Host: ", JSON.stringify( PublicIpAddress ) );

    console.log("postDashboardState response: ", JSON.stringify( response ) );

    console.log(  "Repository ", JSON.stringify( repository ));
    if ( repository.name === '' || (!repository.realDeployment && response.statusCode == 200)) {
        console.log('No repository name or not updating Dashboard, so skip sending deployment state');

        // Allow final states to be unwound before ending this invocation. E.g. Last 'End' is processed.
        context.callbackWaitsForEmptyEventLoop = true;
        callback(null, response);
        context.callbackWaitsForEmptyEventLoop = false;
        return;
    }

    let post_data = {
        "ApplicationName" : repository.name,
        "State" : state
    };
    let post_data_string = JSON.stringify( post_data );
    console.log("post_data: ", post_data_string );
    console.log("post_data length: ", JSON.stringify( post_data_string.length ) );

    // An object of options to indicate where to post to
    let post_options = {
        host: PublicIpAddress,
        port: 443,
        path: '/licensing/ws/paasapi/updatestate?l=eng&p=ils',
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': post_data_string.length
        }
    };
    // Async call
    let post_request = https.request(post_options, function(res) {
        if (res.statusCode === 200) {
            console.log('Status successfully sent to Dashboard ' + post_options.host);

            // Allow final states to be unwound before ending this invocation. E.g. Last 'End' is processed.
            context.callbackWaitsForEmptyEventLoop = true;
            callback(null, response);
            context.callbackWaitsForEmptyEventLoop = false;
        } else {
            returnAPIError( repository.name,  res.statusCode, 'Error ' + res.statusCode + ' posting to Dashboard ' + post_options.host + ':' + post_options.path, callback, context);
            return;
        }

        res.on('end', function() {
            console.log( 'end ' + post_options.host );
        });

        res.on('error', function(e) {
            returnAPIError( repository.name,  res.statusCode, 'Error ' + res.statusCode + ' posting to Dashboard ' + post_options.host + ':' + post_options.path, callback, context);
            return;
        });
    });
    // post the data
    console.log( 'Posting to Dashboard: ', post_options.host, post_options.path );
    post_request.write(post_data_string);
    post_request.end();
}

exports.handler = (event, context, callback) => {
    context.callbackWaitsForEmptyEventLoop = false; // Errors need to be returned ASAP

    let body = '';
    let hostedzoneid = '';
    let alias = '';
    let port = 8101;
    let appl = '';
    let accountwide='n';
    let webserver = false;

    let repository = {
        name : '',
        realDeployment : true
    };

    console.log('event.requestContext.identity: ', event.requestContext.identity );
    console.log('context: ', context );

    // Check that sender is a GitHub server
    // 192.168.196.186 is the ip address of the test server
    // 103.231.169.65/32 is the ip address of LPC
    if ( !ipRangeCheck( event.requestContext.identity.sourceIp, ['185.199.108.0/22', '192.30.252.0/22','140.82.112.0/20','103.231.169.65/32','192.168.196.186']) ) {
        returnAPIError( repository,  403, "Source ip " + event.requestContext.identity.sourceIp + ' is not from a github server', callback, context);
        return;
    }

    // The test code is already a JSON object
    // But when passed through the API Gateway, its not. So simple, when you know ;)
    if ( typeof(event.body) === 'object' ) {
        console.log( 'Body is an object');
        body = event.body;
    } else {
        console.log( 'Body is not an object');
        body = JSON.parse(event.body);
    }
    //console.log( 'body: ', JSON.stringify(body).substring(0, 400));
    //console.log( 'body.repository: ', body.repository );
    console.log( 'body.repository.name: ', body.repository.name );

    repository.name = body.repository.name;
    if (repository.name === '') {
        console.log( "Warning: Repository name not found");
    }

    repository.realDeployment = true;
    if ( body.commits ) {
        if ( body.commits[0] ) {
            // If we have a commit, don't use it's comment as it may not be the only commit.
            // Use the head commit - the latest commit of the set being pushed.
            if ( body.head_commit ) {
                let comment = body.head_commit.message;
                console.log("Comment " + comment );
                if ( comment === 'Setup initial environment') {
                    console.log("Payload contains the first Push, so don't send state to Dashboard");
                    repository.realDeployment = false;
                }
            }
        } else {
            return returnWarning( repository,  "Payload does not contain a commit. Maybe a tag or branch, so don't fanout", callback, context );
        }
    } else if (body.zen) {
        return returnWarning( repository,  "Payload delivered for testing, so don't fanout", callback, context );
    } else {
        return returnWarning( repository,  "Payload unknown, so don't fanout", callback, context );
    }

    // *******************************************************************************************************
    // Check the secret
    // *******************************************************************************************************

    var crypto    = require('crypto');

    var secret    = process.env.SECRET;
    var algorithm = 'sha1';
    var hash, hmac;

    let signature = event.headers['X-Hub-Signature'];
    //console.log( 'signature: ', signature );

    hmac = crypto.createHmac(algorithm, secret);
    hmac.write(JSON.stringify(body)); // write in to the stream
    hmac.end();       // can't read from the stream until you call end()
    hash = hmac.read().toString('hex');    // read out hmac digest
    //console.log("Method 1 JSON.parse: ", hash);

    if ( signature !== ('sha1=' + hash ) ) {
        returnAPIError( repository,  403, 'Error 403 Secret is invalid', callback, context);
        return;
    }

    // *******************************************************************************************************
    // Parameter setup
    // *******************************************************************************************************

    console.log("event.queryStringParameters" + JSON.stringify(event.queryStringParameters));

    if (event.queryStringParameters !== null && event.queryStringParameters !== undefined) {
        if (event.queryStringParameters.hostedzoneid !== undefined &&
            event.queryStringParameters.hostedzoneid !== null &&
            event.queryStringParameters.hostedzoneid !== "") {
            hostedzoneid = event.queryStringParameters.hostedzoneid;
            console.log("Received hostedzoneid: " + hostedzoneid);
        }


        if (event.queryStringParameters.alias !== undefined &&
            event.queryStringParameters.alias !== null &&
            event.queryStringParameters.alias !== "") {
            alias = event.queryStringParameters.alias;
            console.log("Received alias: " + alias);
        }

        if (event.queryStringParameters.port !== undefined &&
            event.queryStringParameters.port !== null &&
            event.queryStringParameters.port !== "") {
            port = event.queryStringParameters.port;
            console.log("Received port: " + port);
        }

        if (event.queryStringParameters.appl !== undefined &&
            event.queryStringParameters.appl !== null &&
            event.queryStringParameters.appl !== "") {
            appl = event.queryStringParameters.appl;
            console.log("Received appl: " + appl);
        }

        if (event.queryStringParameters.accountwide !== undefined &&
            event.queryStringParameters.accountwide !== null &&
            event.queryStringParameters.accountwide !== "") {
            accountwide = event.queryStringParameters.accountwide;
            console.log("Received accountwide: " + accountwide);
        }
    }

    if ( repository.name === '' && accountwide === 'y') {
        returnAPIError( repository,  400, "Error 400 accountwide parameter is set to 'y' but the git repo name cannot be located. Use repo-specific webhook and explicitly specify alias and appl instead", callback, context);
        return;
    }

    // Check if its a repo that we fan out with this code
    let lansaevalMaster = repository.name.indexOf('lansaeval-master');

    let lansarepo = repository.name.indexOf('lansaeval');
    if ( lansarepo < 0 ) {
        lansarepo = repository.name.indexOf('lansapaid');
    }

    if ( (lansarepo < 0 || lansaevalMaster  >= 0) && accountwide === 'y' ){
        return returnWarning( repository,  ' is not handled for accountwide fanning out. Use a repository specific webhook, not account wide', callback, context );
    }

    if ( accountwide !== 'n' && accountwide !== 'y') {
        returnAPIError( repository,  400, "Error 400 accountwide parameter must be 'y' or 'n'. Defaults to 'n'", callback, context);
        return;
    }

    // Mandatory parameters
    if ( hostedzoneid === "" ) {
        returnAPIError( repository,  400, 'Error 400 hostedzoneid is a mandatory parameter', callback, context);
        return;
    }
    if ( accountwide === 'n' && (alias === "" || appl === "") ) {
        returnAPIError( repository,  400, "Error 400 when accountwide = 'n', alias and appl are mandatory parameters", callback, context);
        return;
    }

    if ( accountwide === 'y' && (alias !== "" || appl !== "") ) {
        returnAPIError( repository,  400, "Error 400 when accountwide = 'y', alias and appl must not be specified", callback, context);
        return;
    }

    // If accountwide webhook then derive alias and appl from the repo name
    let stack = 0

    if ( accountwide === 'y') {
        {
            // The repo number indicates the stack and appl to use
            // lansaeval10 use stack 1 and appl 10 (exception to rule 0 = 10)
            // lansaeval11 use stack 1 and appl 1
            // lansaeval21 use stack 2 and appl 1
            // etc

            if ( lansarepo < 0) {
                returnAPIError( repository,  400, "Error 400 only lansaevalxxx and lansapaidxxx repo names are supported when accountwide='y'. All other repo names require explicit alias and appl parameters", callback, context);
                return;
            }

            let repoNumber = repository.name.match( /\d+/g );
            console.log( "repoNumber: ", repoNumber.toString() );

            stack = Math.floor(repoNumber / 10);
            console.log( "stack: ", stack.toString() );

            if ( stack < 1 || stack > 50 ){
                returnAPIError( repository,  400, "Error 400 Repository name " + repository.name + " invalid. Resolves to stack " + stack + " which is less than 1 or greater than 50", callback, context);
                return;
            }

            let applnum = repoNumber % 10;
            if ( applnum === 0) {
                applnum = 10;
            }
            console.log( "applnum: ", applnum.toString() );

            if ( applnum < 1 || applnum > 10 ){
                returnAPIError( repository,  400, "Error 400 Repository name " + repository.name + " invalid. Resolves to application " + applnum + " which is less than 1 or greater than 10", callback, context);
                return;
            }

            alias = 'eval' + stack.toString() + '.paas.lansa.com.';
            appl = 'app' + applnum.toString();
            console.log( "Using alias: %s, appl: %s", alias, appl);
        }
    }

    if ( stack == 20 || stack == 30 ) {
        console.log( "Don't update Dashboard when using the System Test stack - because the Test Dashboard is not publically accessible, nor when using the development stack which is not configured in either Dashboard.")
        repository.realDeployment = false;
    }
    // *******************************************************************************************************
    // Resolving EC2 ip addresses and posting github webhook to each one
    // *******************************************************************************************************

    // Any variables which need to be updated by multiple callbacks need to be declared before the first callback
    // otherwise each callback gets its own copy of the global.

    let instanceCount = 0;
    let successCodes = 0;

    let region = process.env.AWS_DEFAULT_REGION;

    let route53 = new AWS.Route53();

    let paramsListRRS = {
      HostedZoneId: hostedzoneid, /* required - paas.lansa.com */
      MaxItems: '100',
      StartRecordName: alias,
      StartRecordType: 'A'
    };

    // Async call
    route53.listResourceRecordSets(paramsListRRS, function(err, data) {
        if (err) {
            console.log(err, err.stack); // an error occurred
            returnAPIError( repository,  500, err.message, callback, context);
            return;
        }

        // successful response

        console.log('Searched for Alias: ', paramsListRRS.StartRecordName);
        if (data.ResourceRecordSets[0] === undefined ||
            data.ResourceRecordSets[0] === null ||
            data.ResourceRecordSets[0] === "") {

            console.log('Alias not found');
            returnAPIError( repository,  500, 'Alias ' + paramsListRRS.StartRecordName + ' not found', callback, context);
            return;
        }

        // forEach is a Sync call
        let recordSets = data.ResourceRecordSets;
        Object.keys(recordSets).forEach(function(keyRS) {
            console.log('********************************************************************************');
            console.log('Located Alias:      ', recordSets[keyRS].Name);

            // Only use the first record unless this is the webserver repo
            if ( !webserver && 0 != keyRS) {
                return;
            }

            if ( !webserver && paramsListRRS.StartRecordName !== recordSets[keyRS].Name) {
                returnAPIError( repository,  500, 'Searched for Alias is not the one located', callback, context);
                return;
            }

            if ( recordSets[keyRS].Type != 'A' || recordSets[keyRS].AliasTarget === undefined || recordSets[keyRS].AliasTarget.DNSName === undefined) {
                console.log( 'Skipping ', recordSets[keyRS].Name);
                return;
            }

            // For webserver, process all recordsets starting evalx, skip the rest
            if ( webserver && !recordSets[keyRS].Name.match( /eval\d+/ )) {
                console.log( 'Skipping ', recordSets[keyRS].Name);
                return;
            }

            console.log('ELB DNS Name: ', recordSets[keyRS].AliasTarget.DNSName);
            let DNSName = recordSets[keyRS].AliasTarget.DNSName;
            // e.g. paas-livb-webserve-ztessziszyzz-1633164328.us-east-1.elb.amazonaws.com.

            let DNSsplit = DNSName.split(".");
            let ELBNameFull = '';
            let ELBsplit = '';
            console.log( 'DNSsplit[0]: ', DNSsplit[0]);
            if ( DNSsplit[0] === 'dualstack') {
                ELBNameFull = DNSsplit[1];
                region = DNSsplit[2];
            } else {
                ELBNameFull = DNSsplit[0];
                region = DNSsplit[1];
            }
            ELBsplit = ELBNameFull.split("-");
            ELBsplit.pop(); // remove last element

            // Put ELB Name back together again
            let i;
            let ELBLowerCase = '';
            for (i = 0; i < ELBsplit.length; i++) {
                ELBLowerCase += ELBsplit[i];
                if ( i < ELBsplit.length - 1 ) {
                    ELBLowerCase += "-";
                }
            }

            // Need the region to be set before creating these variables.

            let elb = new AWS.ELB();
            let ec2 = new AWS.EC2();

            console.log( 'Region: ' + region );
            console.log( 'ELB:    ' + ELBLowerCase );

            if ( ELBLowerCase === undefined || ELBLowerCase === null || ELBLowerCase === '') {
                // ignore undefined ELB - its an invalid recordset we've found
                return;
            }

            console.log( 'Fanning out to ', ELBLowerCase );

            AWS.config.update({region: region});

            // Async call
            elb.describeLoadBalancers(function(err, data) {
                if (err) {
                    console.log(err, err.stack); // an error occurred
                    returnAPIError( repository,  500, err.message, callback, context);
                    return;
                }

                // successful response
                console.log('Instances: ', JSON.stringify(data.LoadBalancerDescriptions).substring(0,400));
                console.log( 'length: ' , data.LoadBalancerDescriptions.length);

                // Find the lower case ELB name by listing all the load balancers in the region
                // and doing a case insensitive compare

                let i;
                let ELBNum = -1;
                let ELBCurrent = '';
                for (i = 0; i < data.LoadBalancerDescriptions.length; i++) {
                    ELBCurrent =  data.LoadBalancerDescriptions[i].LoadBalancerName.toLowerCase();
                    console.log( 'ELBCurrent: ', ELBCurrent );
                    if ( ELBLowerCase === ELBCurrent) {
                        ELBNum = i;
                        break;
                    }
                }

                if ( ELBNum == -1 ) {
                    if ( webserver ) {
                        // searching through all record sets so may hit an invalid one. Best to keep going and resolve what we can.
                        console.log( 'ELB ' + ELBLowerCase + ' not found. Skipping ');
                        return;
                    }
                    returnAPIError( repository,  500, 'ELB Name not found ' + ELBLowerCase, callback, context);
                    return;
                }

                let instances = data.LoadBalancerDescriptions[ELBNum].Instances;
                if (instances.length === 0) {
                    returnAPIError( repository,  500, 'No instances running in ELB ' + ELBLowerCase, callback, context);
                    return;
                }
                console.log('Instances: ', JSON.stringify(instances).substring(0,400));

                // forEach is a Sync call
                Object.keys(instances).forEach(function(key) {
                    console.log("InstanceId[" + key + "] " + JSON.stringify( instances[key].InstanceId ) );

                    instanceCount++;

                    let params = {
                        DryRun: false,
                        InstanceIds: [
                            instances[key].InstanceId
                        ]
                    };

                    // Async call
                    ec2.describeInstances(params, function(err, data) {
                        if (err) {
                            console.log(err, err.stack); // an error occurred
                            returnAPIError( repository,  500, err.message, callback, context);
                            return;
                        }

                        // successful response
                        // console.log(data.Reservations[0].Instances[0]);
                        let PublicIpAddress = data.Reservations[0].Instances[0].PublicIpAddress;
                        // console.log("Host: ", JSON.stringify( PublicIpAddress ) );

                        // post the payload from GitHub
                        let post_data = '';

                        // console.log("post_data length: ", JSON.stringify( post_data.length ) );

                        // An object of options to indicate where to post to
                        let post_options = {
                            host: PublicIpAddress,
                            port: port,
                            path: '/Deployment/Start/' + appl + '?source=GitHubWebHookReplication',
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json',
                                'Content-Length': post_data.length
                            }
                        };

                        // Async call
                        let post_request = http.request(post_options, function(res) {
                            let body = '';

                            if (res.statusCode === 200) {
                                successCodes++;
                                console.log('Application update successfully deployed by Lambda function to ' + post_options.host);
                                // console.log('successCodes: ' + successCodes + ' instanceCount: ' + instanceCount);
                                if ( successCodes >= instanceCount ){
                                    let message = 'Application update successfully deployed to stack ' + paramsListRRS.StartRecordName + ' application ' + appl + ' repo ' + repository.name + ' using ' + context.invokedFunctionArn;
                                    console.log(message);

                                    let responseBody = {
                                        message: message,
                                        input: event.queryStringParameters
                                    };

                                    // The output from a Lambda proxy integration must be
                                    // of the following JSON object. The 'headers' property
                                    // is for custom response headers in addition to standard
                                    // ones. The 'body' property  must be a JSON string. For
                                    // base64-encoded payload, you must also set the 'isBase64Encoded'
                                    // property to 'true'.
                                    let response = {
                                        statusCode: res.statusCode,
                                        headers: {
                                            "x-custom-header" : "my custom header value"
                                        },
                                        body: JSON.stringify(responseBody)
                                    };
                                    console.log("response: " + JSON.stringify(response));

                                    postDashboardState(repository, "Deployed to Cloud", response, callback, context );
                                }
                            } else {
                                returnAPIError( repository,  res.statusCode, 'Error ' + res.statusCode + ' posting to ' + ELBLowerCase + ' ' + post_options.host + ':' + port + post_options.path, callback, context);
                                return;
                            }

                            res.on('data', function(chunk)  {
                                body += chunk;
                            });

                            res.on('end', function() {
                                console.log( 'end ' + post_options.host );
                                // body is ready to return. Is this needed?
                            });

                            res.on('error', function(e) {
                                returnAPIError( repository,  e.code, e.message + ' Error ' + res.statusCode + ' posting to ' + ELBLowerCase + ' ' + post_options.host + ':' + port + post_options.path, callback, context);
                                return;
                            });
                        });
                        // post the data
                        console.log( 'Posting to:', ELBLowerCase, post_options.host, post_options.path );
                        post_request.write(post_data);
                        post_request.end();
                    });
                });
            });
        });
    });
};
