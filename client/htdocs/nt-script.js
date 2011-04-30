// <script language="JavaScript" type="text/javascript">

// note that we cuddle our elses in here, this is required for some 
// browsers according to: http://en.wikipedia.org/wiki/JavaScript_syntax

function show_rr_edit_rows(rr_type) {

    // alert("rr_type selected is " + rr_type );

    hideThis('tr_weight');
    hideThis('tr_priority');
    hideThis('tr_other');

    switch ( rr_type ) {
        case "A":
            // alert("rr_type selected is A" + rr_type );
            break;
        case "AAAA":
            // alert("rr_type selected is A" + rr_type );
            break;
        case "MX":
            showTableRow('tr_weight');
            break;
        case "NS":
            break;
        case "TXT":
            break;
        case "CNAME":
            break;
        case "PTR":
            break;
        case "SRV":
            // alert("rr_type selected is SRV" + rr_type );
            showTableRow('tr_weight');
            showTableRow('tr_priority');
            showTableRow('tr_other');
            break;
    }
}

function showTableRow(show_me) {
    // show the object we were passed
        var styleObject = getStyleObject(show_me);
        styleObject.visibility = "visible";

    // enables display for hidden blocks
        styleObject.display = "table-row";
}
function showThis(show_me) {
    // show the object we were passed
        var styleObject = getStyleObject(show_me);
        styleObject.visibility = "visible";

    // enables display for hidden blocks
        styleObject.display = "table-row";
}

function hideThis(hide_me) {

    // show the object we were passed
        var styleObject = getStyleObject(hide_me);
        styleObject.visibility = "hidden";

    // enables display for hidden blocks
        styleObject.display = "none";
}

function getStyleObject(objectId) {
        // function getStyleObject(string) -> returns style object
        //  given a string containing the id of an object
        //  the function returns the stylesheet of that object
        //  or false if it can't find a stylesheet.  Handles
        //  cross-browser compatibility issues.
        //
        // checkW3C DOM, then MSIE 4, then NN 4.
        //
        if(document.getElementById && document.getElementById(objectId)) {
                return document.getElementById(objectId).style;
        }
        else if (document.all && document.all(objectId)) {  
                return document.all(objectId).style;
        } 
        else if (document.layers && document.layers[objectId]) { 
                return document.layers[objectId];
        } else {
                alert("could not get elements id" + objectID);
                return false;
        }
}

