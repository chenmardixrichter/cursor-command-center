var SHEET_ID = null; // auto-creates a spreadsheet on first call

function getOrCreateSheet() {
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty('SHEET_ID');
  if (id) {
    try { return SpreadsheetApp.openById(id); } catch (e) { /* recreate */ }
  }
  var ss = SpreadsheetApp.create('Command Center Analytics');

  var events = ss.getSheetByName('Sheet1');
  events.setName('events');
  events.appendRow(['timestamp', 'event', 'user', 'host', 'version', 'userId', 'activeTiles', 'agentTurnsToday', 'raw']);

  var daily = ss.insertSheet('daily');
  daily.appendRow(['timestamp', 'userId', 'macUser', 'version', 'activeTiles', 'agentTurnsToday', 'sessionStart']);

  props.setProperty('SHEET_ID', ss.getId());
  Logger.log('Created analytics sheet: ' + ss.getUrl());
  return ss;
}

function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);
    var ss = getOrCreateSheet();
    var now = new Date().toISOString();
    var event = data.event || 'unknown';

    if (event === 'daily_ping') {
      var daily = ss.getSheetByName('daily');
      daily.appendRow([
        now,
        data.userId || '',
        data.macUser || '',
        data.version || '',
        data.activeTiles || 0,
        data.agentTurnsToday || 0,
        data.sessionStart || ''
      ]);
    }

    var events = ss.getSheetByName('events');
    events.appendRow([
      now,
      event,
      data.user || data.macUser || '',
      data.host || '',
      data.version || '',
      data.userId || '',
      data.activeTiles || '',
      data.agentTurnsToday || '',
      JSON.stringify(data)
    ]);

    return ContentService
      .createTextOutput(JSON.stringify({ status: 'ok' }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ status: 'error', message: err.toString() }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function doGet(e) {
  var ss = getOrCreateSheet();
  return ContentService
    .createTextOutput(JSON.stringify({
      status: 'ok',
      sheetUrl: ss.getUrl(),
      message: 'Command Center Analytics endpoint. POST events here.'
    }))
    .setMimeType(ContentService.MimeType.JSON);
}
