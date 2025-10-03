## [NicTool](http://www.nictool.com)

NicTool is a open source DNS management suite that takes the headaches out of managing DNS data.  NicTool provides a easy to use web interface that allows users with little dns knowledge the ability to manage dns zones and records.

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
* NicTool Client - A CGI application that provides a web interface for managing DNS data. NicTool Client has customizable HTML templates and a CSS style sheet. It is slowly becoming a modern JS web app

### Testimonials and NicTool Users

See
[TESTIMONIALS.md](https://github.com/nictool/NicTool/blob/master/TESTIMONIALS.md)

### Authors

See [AUTHORS.md](https://github.com/nictool/NicTool/blob/master/AUTHORS.md)

### Support

* [Commercial Support](http://www.tnpi.net/cart/index.php/categories/nictool)
* [Forums](http://www.tnpi.net/support/forums/index.php/board,10.0.html)
* [Mailing Lists](https://mail.theartfarm.com/list-archives/?1)
* [Email](mailto:support@nictool.com) - Requests not accompanied by payments are handled on a "best effort" basis.
* [Wiki](https://github.com/nictool/NicTool/wiki)
