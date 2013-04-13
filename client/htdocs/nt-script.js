// <script language="JavaScript" type="text/javascript">

"use strict";

function changeNewZoneName() {
  var zoneName = $('input#zone');
  var mailAddr = $('input#mailaddr');
  if ( mailAddr.val() === 'hostmaster.'+zoneName.val()+'.' )
    return;
  mailAddr.val( 'hostmaster.'+zoneName.val() + '.' );
};

function selectedRRType(rrType) {

    if ( ! rrType ) return false;

    resetZoneRecordFormFields();

    switch (rrType) {
      case 'MX':
        setFormRRTypeMX();    break;
      case 'SRV':
        setFormRRTypeSRV();    break;
      case 'NAPTR':
        setFormRRTypeNAPTR();  break;
      case 'SSHFP':
        setFormRRTypeSSHFP();  break;
      case 'IPSECKEY':
        setFormRRTypeIPSECKEY();break;
      case 'DNSKEY':
        setFormRRTypeDNSKEY(); break;
      case 'DS':
        setFormRRTypeDS();     break;
      case 'NSEC':
        setFormRRTypeNSEC();   break;
      case 'NSEC3':
        setFormRRTypeNSEC3();  break;
      case 'NSEC3PARAM':
        setFormRRTypeNSEC3PARAM(); break;
      case 'RRSIG':
        setFormRRTypeRRSIG();  break;
    }
}

function resetZoneRecordFormFields() {

  var rrOptions = [ 'weight', 'priority', 'other' ];
  for ( var i=0; i < rrOptions.length; i++ ) {
    $('tr#' + rrOptions[i] ).hide();         // hide conditional rows
    $('select#'+rrOptions[i]).hide().empty(); // hide and empty option lists
  };

  var rrAll = $.merge( rrOptions, ['name','address','description'] );
  for ( var i=0; i < rrAll.length; i++ ) {
    $('td#' + rrAll[i] +'_label').text( ucfirst( rrOptions[i] ) );
    $('input#'+rrAll[i])
      .attr('placeholder', '')
      .attr('readonly', false);
  };

  $('td#description_label').text( 'Description' );
  $('input#address').attr('size', 50);
};

function setFormRRTypeMX() {
  $('tr#weight').show();
  $('input#name').attr('placeholder','@');
  $('input#address').attr('placeholder','mail.example.com.');
  $('input#weight').attr('placeholder', '10');
}

function setFormRRTypeSRV() {
  $('tr#weight').show();
  $('tr#priority').show();
  $('tr#other').show();
  $('td#other_label').text('Port');
}

function setFormRRTypeNAPTR() {
  $('tr#weight').show();
  $('td#weight_label').text('Order');

  $('tr#priority').show();
  $('td#priority_label').text('Preference');

  $('td#address_label').text('Flags, Services, Regexp');
  $('td#description_label').text('Replacement');
}

function setFormRRTypeSSHFP() {

    $('td#address_label').text('Fingerprint');

    $('tr#weight').show();
    $('td#weight_label').text('Algorithm');

    var w = $('input#weight');
    if ( w.val() == '' ) w.val('3');
    var selWeight = $('select#weight').show();

    var algoTypes = { '1' : 'RSA', '2' : 'DSA', '3' : 'ECDSA', };
    addValuesToSelect(algoTypes, 'weight');

  $('tr#priority').show();   // Priority field stores the Fingerprint Type
  $('td#priority_label').text('Type');

  var p = $('input#priority');
  if ( p.val() == '' ) p.val('2');   // set the default

  var fpTypes = { '1' : 'SHA-1', '2' : 'SHA-256', };
  addValuesToSelect(fpTypes, 'priority');
}

function setFormRRTypeDNSKEY() {

  $('td#address_label').text('Public Key');

  // Flags: this would be a great place to do an AJAX validation call to the
  // server, and use Net::DNS::SEC to validate this field, and then apply
  // suitable constraints.
  $('tr#weight').show();
  $('td#weight_label').text('Flag');

  $('tr#priority').show();
  $('td#priority_label').text('Protocol');
  $('input#priority').val('3').attr('readonly', true);

  $('tr#other').show();
  $('td#other_label').text('Algorithm');
  var o = $('input#other');
  if ( o.val() == '' ) o.val('5');

  var algoTypes = getDnssecAlgorithms();
  addValuesToSelect(algoTypes, 'other');
}

function setFormRRTypeDS() {

  $('td#address_label').text('Digest');

  $('tr#weight').show();
  $('td#weight_label').text('Key Tag');

  $('tr#priority').show();
  $('td#priority_label').text('Algorithm');
  var p = $('input#priority');
  if ( ! p.val() ) p.val('5');  // RSA/SHA1
  addValuesToSelect( getDnssecAlgorithms(), 'priority');

  $('tr#other').show();
  $('td#other_label').text('Digest Type');
  var o = $('input#other');
  if ( ! o.val() ) o.val('2');
  var digestTypes = { '1' : 'SHA-1', '2' : 'SHA-256', };
  addValuesToSelect( digestTypes, 'other' );
}

function setFormRRTypeNSEC() {
  $('td#address_label').text('Next Domain Name');
  $('td#description_label').text('Type Bit Map');
}
function setFormRRTypeNSEC3() {
}
function setFormRRTypeNSEC3PARAM() {
}
function setFormRRTypeRRSIG() {

/*
 We don't have enough fields in the RR table to enter the 9 pieces of data separately. Instead, just require them to be in the canonical presentation format, and pack it all into the Address field.

host.example.com. 86400 IN RRSIG A 5 3 86400 20030322173103 (
                                  20030220173103 2642 example.com.
                                  oJB1W6WNGv+ldvQ3WDG0MQkg5IEhjRip8WTr
                                  <snip 3 lines>
                                  J5D6fwFm8nN+6pBzeDQfsS3Ap3o= )
*/
  var iA = $('input#address');
  iA.attr('size', 100 )    // suggest that we're expecting a very long value
    .attr('placeholder', 'A 5 3 86400 20030322173103 ( 20030220173103 2642 example.com. oJB1W6...)' );
}

function setFormRRTypeIPSECKEY() {
  $('td#address_label').text('Gateway');
  $('td#description_label').text( 'Public Key' );

  $('tr#weight').show();
  $('td#weight_label').text('Precedence');

  $('tr#priority').show();
  $('td#priority_label').text('Gateway Type');

  $('tr#other').show();
  $('td#other_label').text('Algorithm Type');
//  var p = $('input#other');
//  if ( p.val() == '' ) p.val('2');  // 0=none, 1=DSA, 2=RSA
};

function addValuesToSelect(array,selectName) {
  var selObj = $('select#'+selectName).show();
  $.each(array, function(key, value) {
      selObj
      .append($('<option>', { value : key })
      .text(value));
  });
  selObj.val( $('input#'+selectName).val() );
}

function getDnssecAlgorithms() {
  return {
    '1' : 'RSA/MD5',     '2' : 'Diffie-Hellman',
    '3' : 'DSA/SHA-1',   '4' : 'Elliptic Curve',
    '5' : 'RSA/SHA-1',
  };
};

function ucfirst(string) {
  return string.charAt(0).toUpperCase() + string.slice(1);
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

