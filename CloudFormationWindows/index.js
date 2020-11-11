var response = require('cfn-response');
var AWS = require('aws-sdk');

function addNewRoleToPolicy(dataPolicy,iam){
    var obj = JSON.parse(dataPolicy); //Change dataPolicy from string to json object
    var accountArray = obj.Statement[0].Condition.StringNotLike['aws:userId']; //Get the aws:userId as an array
    if (accountArray.indexOf(iam) === -1) {
        accountArray.push(iam);
    }
     obj.Statement[0].Condition.StringNotLike['aws:userId'] = accountArray;
    //update the policy
    return obj;
    // return the json object of the bucketpolicy
}


exports.handler = (event, context, callback) => {
    var s3 = new AWS.S3();
    var bkname = event.ResourceProperties.bucketname;
    var iamname = event.ResourceProperties.iam;
    
    var params = {
        Bucket: bkname
    };
    
    
    s3.getBucketPolicy(params, function(err, data) {
    if (err) {
        console.log(err, err.stack);
        response.send(event, context, response.FAILED);
    } // an error occurred
    else {
        var params2 = {
            Bucket: bkname, 
            Policy: JSON.stringify(addNewRoleToPolicy(data.Policy,iamname))
        };
    s3.putBucketPolicy(params2, function(err, data) {
        if (err) {
            console.log(err, err.stack);
            response.send(event, context, response.FAILED);
        }// an error occurred
        else {
            console.log("updated: "+data);
            response.send(event, context, response.SUCCESS);
        } 
    });
    }
 });
    
    //callback(null, "Done");
};