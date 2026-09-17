const SHEET_NAME = "INVENTORY"; // tab name in your Google Sheet

const HEADERS = [
  "Timestamp", "Hostname", "IPAddress", "MACAddress", "CurrentUser", "DomainWorkgroup",
  "Manufacturer", "Model", "SerialNumber", "CPU", "GPU", "RAM_GB", "Storage",
  "WindowsVersion", "Uptime", "Monitor", "Keyboard", "Mouse", "Printers"
];

function doPost(e) {
  const sheet = getOrCreateSheet();
  const data = JSON.parse(e.postData.contents);

  if (sheet.getLastRow() === 0) {
    sheet.appendRow(HEADERS);
  }

  const row = HEADERS.map(h => data[h] !== undefined ? data[h] : "");

  // SerialNumber is the unique key - find its column and search existing rows
  const serialCol = HEADERS.indexOf("SerialNumber") + 1; // 1-based for Sheets API
  const lastRow = sheet.getLastRow();

  let matchedRow = -1;
  if (lastRow > 1) {
    const serials = sheet.getRange(2, serialCol, lastRow - 1, 1).getValues();
    for (let i = 0; i < serials.length; i++) {
      if (String(serials[i][0]).trim() === String(data.SerialNumber).trim()) {
        matchedRow = i + 2; // +2 because data starts at row 2 (row 1 = headers)
        break;
      }
    }
  }

  let status, resultRow;
  if (matchedRow > 0) {
    // Overwrite the existing row for this serial number
    sheet.getRange(matchedRow, 1, 1, row.length).setValues([row]);
    status = "updated";
    resultRow = matchedRow;
  } else {
    sheet.appendRow(row);
    status = "added";
    resultRow = sheet.getLastRow();
  }

  return ContentService
    .createTextOutput(JSON.stringify({ status: status, row: resultRow, hostname: data.Hostname }))
    .setMimeType(ContentService.MimeType.JSON);
}

function doGet(e) {
  return ContentService
    .createTextOutput("Inventory collector is live.")
    .setMimeType(ContentService.MimeType.TEXT);
}

function getOrCreateSheet() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
  }
  return sheet;
}
