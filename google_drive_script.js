// =====================================================
// Google Apps Script — LTP PDF Manager
// วิธีติดตั้ง:
// 1. ไปที่ script.google.com > New project
// 2. วางโค้ดนี้ทั้งหมด
// 3. Deploy > New deployment > Web app
//    - Execute as: Me
//    - Who has access: Anyone
// 4. Copy URL มาใส่ในระบบ LTP
// =====================================================

const FOLDER_NAME = 'LTP ระบบภาษี';
const ALLOWED_ORIGINS = ['*']; // ใส่ domain จริงถ้าต้องการ restrict

function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const action = data.action;

    if (action === 'upload') {
      return uploadFile(data);
    } else if (action === 'delete') {
      return deleteFile(data.fileId);
    } else if (action === 'list') {
      return listFiles(data.subfolder);
    }
    return respond({ error: 'Unknown action' }, 400);
  } catch(err) {
    return respond({ error: err.message }, 500);
  }
}

function doGet(e) {
  const fileId = e.parameter.fileId;
  if (fileId) {
    // redirect to file
    const file = DriveApp.getFileById(fileId);
    return HtmlService.createHtmlOutput(
      `<script>window.location='${file.getUrl()}'</script>`
    );
  }
  return respond({ status: 'LTP PDF Manager running' });
}

function getLTPFolder(subfolder) {
  let root;
  const folders = DriveApp.getFoldersByName(FOLDER_NAME);
  if (folders.hasNext()) {
    root = folders.next();
  } else {
    root = DriveApp.createFolder(FOLDER_NAME);
  }

  if (!subfolder) return root;

  const subs = root.getFoldersByName(subfolder);
  if (subs.hasNext()) return subs.next();
  return root.createFolder(subfolder);
}

function uploadFile(data) {
  // data = { action, base64, filename, mimeType, subfolder, refId }
  const bytes = Utilities.base64Decode(data.base64);
  const blob = Utilities.newBlob(bytes, data.mimeType || 'application/pdf', data.filename);

  const folder = getLTPFolder(data.subfolder || 'ทั่วไป');
  const file = folder.createFile(blob);

  // เปิดให้ดูได้ (แต่ไม่แก้ไข)
  file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);

  return respond({
    success: true,
    fileId: file.getId(),
    url: file.getUrl(),
    viewUrl: 'https://drive.google.com/file/d/' + file.getId() + '/view',
    name: file.getName(),
    size: file.getSize()
  });
}

function deleteFile(fileId) {
  try {
    DriveApp.getFileById(fileId).setTrashed(true);
    return respond({ success: true });
  } catch(e) {
    return respond({ error: e.message }, 404);
  }
}

function listFiles(subfolder) {
  const folder = getLTPFolder(subfolder);
  const files = folder.getFiles();
  const result = [];
  while (files.hasNext()) {
    const f = files.next();
    result.push({
      id: f.getId(),
      name: f.getName(),
      url: f.getUrl(),
      size: f.getSize(),
      date: f.getDateCreated()
    });
  }
  return respond({ files: result });
}

function respond(data, code) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}
