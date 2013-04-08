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
        $('tr#tr_weight').show();
        break;
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
        setFormRRTypeNSEC();   break;
      case 'NSEC3PARAM':
        setFormRRTypeNSEC();   break;
      case 'RRSIG':
        setFormRRTypeRRSIG();  break;
    }
}

function resetZoneRecordFormFields() {

  var rrFields = [ 'address', 'weight', 'priority', 'other' ];
  for ( var i=0; i < rrFields.length; i++ ) {
    $('tr#tr_' + rrFields[i] ).hide();
    $('td#'+rrFields[i] +'_label').text( ucfirst( rrFields[i] ) );
  };

  $('input#priority' ).attr('readonly', false);
  $('td#description_label').text( 'Description' );
};

function setFormRRTypeSRV() {
    $('tr#tr_weight').show();
    $('tr#tr_priority').show();
    $('tr#tr_other').show();
    $('td#other_label').text('Port');
}

function setFormRRTypeNAPTR() {
    $('tr#tr_weight').show();
    $('td#weight_label').text('Order');

    $('tr#tr_priority').show();
    $('td#priority_label').text('Preference');

    $('td#address_label').text('Flags, Services, Regexp');
    $('td#description_label').text('Replacement');
}

function setFormRRTypeSSHFP() {

    $('td#address_label').text('Fingerprint');

    $('tr#tr_weight').show();
    $('td#weight_label').text('Algorithm');
    var w = $('input#weight');
    if ( w.val() == '' ) w.val('3');   // 1=RSA, 2=DSS, 3=ECDSA

    $('tr#tr_priority').show();
    $('td#priority_label').text('Type');
    var p = $('input#priority');
    if ( p.val() == '' ) p.val('2');  // 1=SHA-1, 2=SHA-256
}

function setFormRRTypeDNSKEY() {

    $('td#address_label').text('Public Key');

    $('tr#tr_weight').show();
    $('td#weight_label').text('Flag');

    $('tr#tr_priority').show();
    $('td#priority_label').text('Protocol');
    $('input#priority').val('3').attr('readonly', true);

    // 1=RSA/MD5, 2=Diffie-Hellman, 3=DSA/SHA-1, 4=Elliptic Curve, 5=RSA/SHA-1
    $('tr#tr_other').show();
    $('td#other_label').text('Algorithm');
    var o = $('input#other');
    if ( o.val() == '' ) o.val('5');
}

function setFormRRTypeDS() {

    $('td#address_label').text('Digest');

    $('tr#tr_weight').show();
    $('td#weight_label').text('Key Tag');

    $('tr#tr_priority').show();
    $('td#priority_label').text('Algorithm');
    var p = $('input#priority');
    if ( ! p.val() ) p.val('5');  // RSA/SHA1

    $('tr#tr_other').show();
    $('td#other_label').text('Digest Type');
    var o = $('input#other');
    if ( ! o.val() ) o.val('2');  // 1=SHA-1 , 2=SHA-256
}

function setFormRRTypeNSEC() {
    $('td#address_label').text('Next Domain Name');
    $('td#description_label').text('Type Bit Map');
}
function setFormRRTypeRRSIG() {
}

function setFormRRTypeIPSECKEY() {
  $('td#address_label').text('Gateway');
  $('td#description_label').text( 'Public Key' );

  $('tr#tr_weight').show();
  $('td#weight_label').text('Precedence');

  $('tr#tr_priority').show();
  $('td#priority_label').text('Gateway Type');

  $('tr#tr_other').show();
  $('td#other_label').text('Algorithm Type');
//  var p = $('input#other');
//  if ( p.val() == '' ) p.val('2');  // 0=none, 1=DSA, 2=RSA
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

