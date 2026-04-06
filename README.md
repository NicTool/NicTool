## [NicTool](http://www.nictool.com)

NicTool is an open source DNS management suite that takes the headaches out of managing DNS data. NicTool provides an easy-to-use web interface that allows users with little DNS knowledge the ability to manage DNS zones and records.

### Features

* Web interface for users, admins, and clients
* Validation of DNS data before acceptance
* Permissions for users and groups
* Delegatation of zones and zone records to users and/or groups
* Logging of all DNS changes (who did what & when)
* RDBMS data storage
* API for automation and integration

### Supported formats for exporting DNS data to servers

* [djbdns / ndjbdns (tinydns)](https://github.com/nictool/NicTool/wiki/Export-to-tinydns)
* [BIND](https://github.com/nictool/NicTool/wiki/Export-to-BIND)
* [PowerDNS](https://github.com/nictool/NicTool/wiki/Export-to-PowerDNS)
* [DynECT](https://github.com/nictool/NicTool/wiki/Export-to-DynECT-Managed-DNS)
* [Knot DNS](https://github.com/nictool/NicTool/wiki/Install-Knot)
* [NSD](https://github.com/nictool/NicTool/wiki/Install-NSD)
* [MaraDNS](https://github.com/nictool/NicTool/wiki/Install-MaraDNS)

### Supported formats for [importing](https://github.com/nictool/NicTool/wiki/Imports) existing DNS data

* [BIND](https://github.com/nictool/NicTool/wiki/Import-from-BIND)
* [djbdns / ndjbdns (tinydns)](https://github.com/nictool/NicTool/wiki/Import-from-tinydns)

### Components

* NicTool Server - Exposes the DNS data via a SOAP web service.
* NicTool API - The NicTool API is what connects to the NicTool Server. The format of requests is defined in the reference API at http://www.nictool.com/docs/api/
* NicTool Client - A CGI application that provides a web interface for managing DNS data. NicTool Client has customizable HTML templates and a CSS style sheet.

### NicTool 3

The next generation of NicTool is a JavaScript rewrite at [github.com/NicTool/api](https://github.com/NicTool/api) (v3, Node.js + REST API). Related `@nictool` npm packages:

* [validate](https://www.npmjs.com/package/@nictool/validate)
* [dns-resource-record](https://www.npmjs.com/package/@nictool/dns-resource-record)
* [dns-zone](https://www.npmjs.com/package/@nictool/dns-zone)
* [dns-nameserver](https://www.npmjs.com/package/@nictool/dns-nameserver)

### Testimonials and NicTool Users

See
[TESTIMONIALS.md](https://github.com/nictool/NicTool/blob/master/TESTIMONIALS.md)

### Authors

See [AUTHORS.md](https://github.com/nictool/NicTool/blob/master/AUTHORS.md)

### Support

* [Commercial Support](https://www.tnpi.net/cart/index.php/categories/nictool)
* [Email](mailto:support@nictool.com) - Requests not accompanied by payments are handled on a "best effort" basis.
* [GitHub Issues](https://github.com/NicTool/NicTool/issues)
* [Wiki](https://github.com/nictool/NicTool/wiki)
