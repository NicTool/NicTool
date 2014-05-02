// <script language="JavaScript" type="text/javascript">

"use strict";

function changeNewZoneName() {
  var zoneName = $('input#zone');
  var mailAddr = $('input#mailaddr');
  if (mailAddr.val() === 'hostmaster.'+zoneName.val()+'.') return;
  mailAddr.val('hostmaster.'+zoneName.val() + '.');
};

function changeRRType(rrType) {
    if (!rrType) return false;

		var rrOptions = [ 'weight', 'priority', 'other' ];
		for ( var i=0; i < rrOptions.length; i++ ) {
				$('input#' +rrOptions[i]).val('');
		}

		selectedRRType(rrType);
}

function selectedRRType(rrType) {

    if (!rrType) return false;
    resetZoneRecordFormFields();

    switch (rrType) {
      case 'A':          setFormRRTypeA();          break;
      case 'AAAA':       setFormRRTypeAAAA();       break;
      case 'NS':         setFormRRTypeNS();         break;
      case 'MX':         setFormRRTypeMX();         break;
      case 'CNAME':      setFormRRTypeCNAME();      break;
      case 'DNAME':      setFormRRTypeDNAME();      break;
      case 'SRV':        setFormRRTypeSRV();        break;
      case 'SPF':        setFormRRTypeSPF();        break;
      case 'NAPTR':      setFormRRTypeNAPTR();      break;
      case 'LOC':        setFormRRTypeLOC();        break;
      case 'SSHFP':      setFormRRTypeSSHFP();      break;
      case 'IPSECKEY':   setFormRRTypeIPSECKEY();   break;
      case 'DNSKEY':     setFormRRTypeDNSKEY();     break;
      case 'DS':         setFormRRTypeDS();         break;
      case 'NSEC':       setFormRRTypeNSEC();       break;
      case 'NSEC3':      setFormRRTypeNSEC3();      break;
      case 'NSEC3PARAM': setFormRRTypeNSEC3PARAM(); break;
      case 'RRSIG':      setFormRRTypeRRSIG();      break;
    }
}

function resetZoneRecordFormFields() {

  var rrOptions = [ 'weight', 'priority', 'other' ];
  for ( var i=0; i < rrOptions.length; i++ ) {
    $('tr#' + rrOptions[i] ).hide();         // hide conditional rows
    $('select#'+rrOptions[i]).hide().empty(); // hide and empty option lists
  };

  var rrAll = $.merge(rrOptions, ['name','address','description']);
  for ( var i=0; i < rrAll.length; i++ ) {
    $('td#' + rrAll[i] +'_label').text(ucfirst(rrOptions[i]));
    $('input#'+rrAll[i])
      .attr('placeholder', '')
      .attr('readonly', false);
  };

  $('td#description_label').text('Description');
  $('input#address').attr('size', 50);
  $('span#rfc_help').html('');
};

function setFormRRTypeA() {
  setRfcHelp(['1035']);
  $('input#name').attr('placeholder','host');
  $('input#address').attr('placeholder','192.0.99.5');
}

function setFormRRTypeAAAA() {
  setRfcHelp(['3596']);
  $('input#name').attr('placeholder','host');
  $('input#address').attr('placeholder','2001:db8:f00d::2');
}

function setFormRRTypeNS() {
  setRfcHelp(['1035']);
  $('input#name').attr('placeholder','subdomain');
  $('input#address').attr('placeholder','ns1.example.com.');
}

function setFormRRTypeMX() {
  setRfcHelp(['1035']);
  $('tr#weight').show();
  $('input#name').attr('placeholder','@');
  $('input#address').attr('placeholder','mail.example.com.');
  $('input#weight').attr('placeholder', '10');
}

function setFormRRTypeCNAME() {
  setRfcHelp(['1035']);
  $('input#name').attr('placeholder','host');
  $('input#address').attr('placeholder','fqdn.example.com.');
}

function setFormRRTypeDNAME() {
  setRfcHelp(['2672']);
  $('input#name').attr('placeholder','subdomain');
  $('td#address_label').text('Target');
  $('input#address').attr('placeholder','fqdn.example.com.');
}

function setFormRRTypeSRV() {
  setRfcHelp(['2782']);
  $('input#name').attr('placeholder','_dns._udp');
  $('input#address').attr('placeholder','ns1.example.com.');

  $('tr#weight').show();
  $('input#weight').attr('placeholder','10');

  $('tr#priority').show();

  $('tr#other').show();
  $('td#other_label').text('Port');
  $('input#other').attr('placeholder','53');
}

function setFormRRTypeSPF() {
  setRfcHelp(['4408']);
  $('input#name').attr('placeholder','@');
  $('input#address').attr('placeholder','v=spf1 mx a -all');
}

function setFormRRTypeNAPTR() {
  setRfcHelp(['3403']);
  $('tr#weight').show();
  $('td#weight_label').text('Order');
  $('input#weight').attr('placeholder','100');

  $('tr#priority').show();
  $('td#priority_label').text('Preference');
  $('input#priority').attr('placeholder','10');

  $('td#address_label').text('Flags, Services, Regexp');
  $('input#address').attr('placeholder','"" "" "/urn:cid:.+@([^\\.]+\\.)(.*)$/\\2/i"');

  $('td#description_label').text('Replacement');
}

function setFormRRTypeLOC() {
  setRfcHelp(['1876']);
  $('input#name').attr('placeholder','host');
  $('input#address')
    .attr('placeholder','47 43 47.000 N 122 21 35.000 W 132.00m 100m 100m 2m')
    .attr('size', 65);
  $('td#address_label').text('Location');
}

function setFormRRTypeSSHFP() {
  setRfcHelp(['4255']);

  $('input#name').attr('placeholder','host');

  $('td#address_label').text('Fingerprint');
  $('input#address').attr('placeholder','hint: ssh-keygen -r');

  $('tr#weight').show();
  $('td#weight_label').text('Algorithm');
  $('input#weight').attr('placeholder','3');
  var algoTypes = { '1' : 'RSA', '2' : 'DSA', '3' : 'ECDSA' };
  addValuesToSelect(algoTypes, 'weight');
  $('select#weight').show();

  $('tr#priority').show();   // Priority field stores the Fingerprint Type
  $('td#priority_label').text('Type');
  $('input#priority').attr('placeholder','2');
  addValuesToSelect( { '1' : 'SHA-1', '2' : 'SHA-256', }, 'priority');
  $('select#priority').show();
}

function setFormRRTypeDNSKEY() {
  setRfcHelp(['4034']);

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
  setRfcHelp(['4034']);

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
  setRfcHelp(['4034']);
  $('td#address_label').text('Next Domain Name');
  $('input#address').attr('placeholder','host.example.com.');

  $('td#description_label').text('Type Bit Map');
  $('input#description').attr('placeholder','A MX TXT');
}
function setFormRRTypeNSEC3() {
  setRfcHelp(['5155']);
  $('input#address')
    .attr('placeholder', '1 1 12 aabbccdd ( 2t7b4g4vsa5smi47k61mv5bv1a22bojr MX DNSKEY NS SOA NSEC3PARAM RRSIG )')
    .attr('size', 100 );
}
function setFormRRTypeNSEC3PARAM() {
  setRfcHelp(['5155']);
  $('input#address')
    .attr('placeholder', '1 1 12 aa99ffdd');
}

function setFormRRTypeRRSIG() {
  setRfcHelp(['4034']);

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
  setRfcHelp(['4025']);
  $('td#address_label').text('Gateway');
  $('td#description_label').text( 'Public Key' );

  $('tr#weight').show();
  $('td#weight_label').text('Precedence');

  $('tr#priority').show();
  $('td#priority_label').text('Gateway Type');
  var gwTypes = {
    '0' : 'none',          '1' : 'IPv4 address',
    '2' : 'IPv6 address',  '3' : 'domain name',
  };
  addValuesToSelect( gwTypes, 'priority' );

  $('tr#other').show();
  $('td#other_label').text('Algorithm Type');
  $('input#other').attr('placeholder','2');
  var algoTypes = { '0' : 'none', '1' : 'DSA', '2' : 'RSA', };
  addValuesToSelect( algoTypes, 'other' );
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
// http://www.iana.org/assignments/dns-sec-alg-numbers/dns-sec-alg-numbers.xhtml
  return {
    '1' : 'RSA/MD5 (deprecated)', '2' : 'Diffie-Hellman',
    '3' : 'DSA/SHA-1',            '4' : 'Elliptic Curve (deprecated)',
    '5' : 'RSA/SHA-1',            '6' : 'DSA-NSEC3-SHA1',
    '7' : 'RSASHA1-NSEC3-SHA1',   '8' : 'RSA/SHA-256',
    '10': 'RSA/SHA-512',          '12': 'GOST R 34.10-2001',
    '13': 'ECDSA Curve P-256 with SHA-256',
    '14': 'ECDSA Curve P-384 with SHA-384',
  };
};

function ucfirst(string) {
  return string.charAt(0).toUpperCase() + string.slice(1);
}

function setRfcHelp(rfcList) {
  for (var i=0; i < rfcList.length; i++) {
    $('span#rfc_help').html(
      $('span#rfc_help').html() +
        ' <a target="_blank" href="https://tools.ietf.org/html/rfc'+rfcList[i]+'">RFC '+rfcList[i]+'</a>'
    );
  };
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

