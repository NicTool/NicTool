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

