// <script language="JavaScript" type="text/javascript">

"use strict";

function getStyleObject(objectId) {
    /* function getStyleObject(string) -> returns style object
    **  given a string containing the id of an object
    **  the function returns the stylesheet of that object
    **  or false. 
    **  Should handle browser compatibility issues.
    */
    if (document.getElementById && document.getElementById(objectId)) {
        return document.getElementById(objectId).style; // W3C DOM
    }
    if (document.all && document.all(objectId)) {
        return document.all(objectId).style; // MSIE 4
    }
    if (document.layers && document.layers[objectId]) {
        return document.layers[objectId]; // NN 4
    }
    alert('could not get element id: ' + objectId);
    return false;
}

function hideThis(hideMe) {

    var styleObject = getStyleObject(hideMe); // get the DOM object

    // http://www.w3.org/wiki/CSS/Properties/visibility
    styleObject.visibility = "hidden";
    // http://www.w3.org/wiki/CSS/Properties/display
    styleObject.display = "none";
}

function showTableRow(showMe) {
    var styleObject = getStyleObject(showMe);

    // display the hidden row
    styleObject.visibility = "visible";
    styleObject.display = "table-row";
}

function showFieldsForRRtype(rrType) {

    // alert("rrType selected is " + rrType );

    if (!getStyleObject('tr_weight') ){
// RR edit form is not displayed, don't try updating it.
        return false;
    }
    hideThis('tr_weight');
    hideThis('tr_priority');
    hideThis('tr_other');

    switch (rrType) {
    case 'A':
        // alert("rrType selected is A-" + rrType );
        break;
    case 'AAAA':
        break;
    case 'MX':
        showTableRow('tr_weight');
        break;
    case 'NS':
        break;
    case 'TXT':
        break;
    case 'CNAME':
        break;
    case 'PTR':
        break;
    case 'SRV':
        // alert("rrType selected is SRV" + rrType );
        showTableRow('tr_weight');
        showTableRow('tr_priority');
        showTableRow('tr_other');
        break;
    }
}

function showThis(showMe) {
    var styleObject = getStyleObject(showMe);
    styleObject.visibility = "visible";
    styleObject.display = "block";
}
function showMenuItem(showMe) {
    var styleObject = getStyleObject(showMe);
    styleObject.visibility = "visible";
    styleObject.display = "inline";
}

//access types
function selectAllEdit(pForm, pAction) {
    if (pForm.group_write) { pForm.group_write.checked = pAction; }
    if (pForm.user_write) { pForm.user_write.checked = pAction; }
    if (pForm.zone_write) { pForm.zone_write.checked = pAction; }
    if (pForm.zonerecord_write) { pForm.zonerecord_write.checked = pAction; }
    if (pForm.nameserver_write) { pForm.nameserver_write.checked = pAction; }
    if (pForm.self_write) { pForm.self_write.checked = pAction; }
}
function selectAllCreate(pForm, pAction) {
    if (pForm.group_create) { pForm.group_create.checked = pAction; }
    if (pForm.user_create) { pForm.user_create.checked = pAction; }
    if (pForm.zone_create) { pForm.zone_create.checked = pAction; }
    if (pForm.zonerecord_create) { pForm.zonerecord_create.checked = pAction; }
    if (pForm.nameserver_create) { pForm.nameserver_create.checked = pAction; }
}
function selectAllDelete(pForm, pAction) {
    if (pForm.group_delete) { pForm.group_delete.checked = pAction; }
    if (pForm.user_delete) { pForm.user_delete.checked = pAction; }
    if (pForm.zone_delete) { pForm.zone_delete.checked = pAction; }
    if (pForm.zonerecord_delete) { pForm.zonerecord_delete.checked = pAction; }
    if (pForm.nameserver_delete) { pForm.nameserver_delete.checked = pAction; }
}
function selectAllDelegate(pForm, pAction) {
    if (pForm.zone_delegate) { pForm.zone_delegate.checked = pAction; }
    if (pForm.zonerecord_delegate) {
        pForm.zonerecord_delegate.checked = pAction;
    }
}
function selectAllAll(pForm, pAction) {
    selectAllEdit(pForm, pAction);
    selectAllCreate(pForm, pAction);
    selectAllDelete(pForm, pAction);
    selectAllDelegate(pForm, pAction);
}

//object types
function selectAllGroup(pForm, pAction) {
    if (pForm.group_write) { pForm.group_write.checked = pAction; }
    if (pForm.group_create) { pForm.group_create.checked = pAction; }
    if (pForm.group_delete) { pForm.group_delete.checked = pAction; }
}
function selectAllUser(pForm, pAction) {
    if (pForm.user_write) { pForm.user_write.checked = pAction; }
    if (pForm.user_create) { pForm.user_create.checked = pAction; }
    if (pForm.user_delete) { pForm.user_delete.checked = pAction; }
}
function selectAllZone(pForm, pAction) {
    if (pForm.zone_create) { pForm.zone_create.checked = pAction; }
    if (pForm.zone_write) { pForm.zone_write.checked = pAction; }
    if (pForm.zone_delete) { pForm.zone_delete.checked = pAction; }
    if (pForm.zone_delegate) { pForm.zone_delegate.checked = pAction; }
}
function selectAllZonerecord(pForm, pAction) {
    if (pForm.zonerecord_write) { pForm.zonerecord_write.checked = pAction; }
    if (pForm.zonerecord_create) { pForm.zonerecord_create.checked = pAction; }
    if (pForm.zonerecord_delete) { pForm.zonerecord_delete.checked = pAction; }
    if (pForm.zonerecord_delegate) { pForm.zonerecord_delegate.checked = pAction; }
}
function selectAllNameserver(pForm, pAction) {
    if (pForm.nameserver_write) { pForm.nameserver_write.checked = pAction; }
    if (pForm.nameserver_create) { pForm.nameserver_create.checked = pAction; }
    if (pForm.nameserver_delete) { pForm.nameserver_delete.checked = pAction; }
}
function selectAllSelf(pForm, pAction) {
    if (pForm.self_write) { pForm.self_write.checked = pAction; }
}

