import ballerina/http;
import ballerina/url;
import ballerina/log;
import ballerina/os;
import ballerinax/googleapis.sheets as sheets;

configurable string timeDuration = "24h";
configurable string queryPullCount = string `let mainTable = customEvents
| where timestamp > ago(${timeDuration})
| where name == "package-pull" ;
let x = mainTable
| summarize Count = count() by client_CountryOrRegion, Event = "package-pull";
x ;`;

configurable string queryPushCount = string `let mainTable = customEvents
| where timestamp > ago(${timeDuration})
| where name == "package-push" ;
let x = mainTable
| summarize Count = count() by client_CountryOrRegion, Event = "package-push" , package = tostring(customDimensions["name"]) , org = tostring(customDimensions["organization"]);
x ;`;

configurable string queryDistDownloadCount = string `let mainTable = customEvents
| where timestamp > ago(${timeDuration})
| where name == "distribution-download";
let y = mainTable
| summarize Count = count() by client_CountryOrRegion, Event = "distribution-download" , Version = tostring(customDimensions["downloadedDistVersion"]);
y;`;

configurable string queryPackages = string `let mainTable = customEvents
| where timestamp > ago(${timeDuration})
| where name == "package-pull";
let x = mainTable
| summarize PullCount = count() by tostring(customDimensions["name"]) ,  org = tostring(customDimensions["organization"]) 
| sort by PullCount desc;
x ;`;

configurable string spreadsheetClientID = "721896546129-45fubg5ij5m84qoikbnqgu73u1bhvh4f.apps.googleusercontent.com";
configurable string spreadsheetClientSecret = "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";
configurable string spreadsheetRefreshToken = "1//04su8tUCzoEvoCgYIARAAGAQSNwF-L9IrqC9NbLeo1xRlVG3PCKNATdZ5Th6TbPJQiyWUwsj5kq_SEYlAvZWlcXN-muvtfy7vAFE";

public function main() returns error? {
    string applicationID = os:getEnv("bcentral_stage_APPLICATION_ID");
    string apiKey = os:getEnv("bcentral_stage_API_KEY");

    http:Client http = check new http:Client(string `https://api.applicationinsights.io/v1/apps/${applicationID}`);

    map<(string|string[])>? headers = {
        "x-api-key": apiKey
    };

    sheets:ConnectionConfig spreadsheetConfig = {
        auth: {
            clientId: spreadsheetClientID,
            clientSecret: spreadsheetClientSecret,
            refreshUrl: sheets:REFRESH_URL,
            refreshToken: spreadsheetRefreshToken
        }
    };

    sheets:Client spreadsheetClient = check new (spreadsheetConfig);
    sheets:Spreadsheet spreadsheet = check spreadsheetClient->createSpreadsheet("DashboardExtractor");

    // pull count
    string encodedQuery = check url:encode(queryPullCount, "UTF-8");
    string path = string `/query?query=${encodedQuery}`;
    http:Response response = check http->get(path, headers);
    json jsonPayload = check response.getJsonPayload();
    string[][] jsonPayloadExtractorResult = check jsonPayloadExtractor(jsonPayload);

    _ = check excelWriter(jsonPayloadExtractorResult, spreadsheetClient, spreadsheet.spreadsheetId, "Country-wise Count - Pull packages count");

    // pull count
    encodedQuery = check url:encode(queryPushCount, "UTF-8");
    path = string `/query?query=${encodedQuery}`;
    response = check http->get(path, headers);
    jsonPayload = check response.getJsonPayload();
    jsonPayloadExtractorResult = check jsonPayloadExtractor(jsonPayload);

    _ = check excelWriter(jsonPayloadExtractorResult, spreadsheetClient, spreadsheet.spreadsheetId, "Country-wise Count - Push packages count");

    // download count
    encodedQuery = check url:encode(queryDistDownloadCount, "UTF-8");
    path = string `/query?query=${encodedQuery}`;
    response = check http->get(path, headers);
    jsonPayload = check response.getJsonPayload();
    jsonPayloadExtractorResult = check jsonPayloadExtractor(jsonPayload);

    _ = check excelWriter(jsonPayloadExtractorResult, spreadsheetClient, spreadsheet.spreadsheetId, "Country-wise Count - Distribution download count");

    // packages - pull count
    encodedQuery = check url:encode(queryPackages, "UTF-8");
    path = string `/query?query=${encodedQuery}`;
    response = check http->get(path, headers);
    jsonPayload = check response.getJsonPayload();
    jsonPayloadExtractorResult = check jsonPayloadExtractor(jsonPayload);

    _ = check excelWriter(jsonPayloadExtractorResult, spreadsheetClient, spreadsheet.spreadsheetId, "Packages - on Pull packages count");

}

# Description of the function.
#
# + jsonPayload - Response of the http request
# + return - Rows to be inserted to the excel sheet
public function jsonPayloadExtractor(json jsonPayload) returns string[][]|error {

    string[] data = [];
    string[][] excelRows = [];
    int columnCount = 0;
    json[] content = check (check jsonPayload.tables).fromJsonWithType();
    log:printInfo(content.toString());
    json[][] dataRows = check (check content[0].rows).fromJsonWithType();
    json[] columns = check (check content[0].columns).fromJsonWithType();

    foreach var item in columns {
        string column = check (check item.name).fromJsonWithType();
        data.push(column);
        columnCount += 1;
    }

    excelRows.push(data);

    foreach json[] item in dataRows {
        data = [];
        foreach int i in 0 ... columnCount - 1 {
            data.push(item[i].toString());
        }
        excelRows.push(data);
    }

    return excelRows;

}

# Description of the function.
#
# + data - data needed to be inserted to the excel sheet
# + spreadsheetClient - spreadsheetClient configured
# + spreadsheetID - spreadsheetID of a specific sheet
# + sheetName - name of the sheet needed to be created
# + return - Return error if failed otherwise ?
public function excelWriter(string[][] data, sheets:Client spreadsheetClient, string spreadsheetID, string sheetName) returns error? {

    _ = check spreadsheetClient->addSheet(spreadsheetID, sheetName);

    sheets:A1Range a1Range = {
        sheetName: sheetName
    };

    foreach string[] item in data {
        _ = check spreadsheetClient->appendValue(spreadsheetID, item, a1Range);
    }

    return ();
}
