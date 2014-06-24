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

* djbdns / ndjbdns (tinydns)
* BIND
* PowerDNS
* DynECT
* Knot DNS
* NSD
* MaraDNS

### Supported formats for importing existing DNS data

* BIND
* djbdns / ndjbdns (tinydns)

### Components

* NicTool Server - Exposes the DNS data via a SOAP web service.
* NicTool API - The NicTool API is what connects to the NicTool Server. The format of requests is defined in the reference API at http://www.nictool.com/docs/api/
* NicTool Client - A CGI application thatt provides a web interface for managing DNS data. NicTool Client has customizable HTML templates and a CSS style sheet. It is slowly becoming a modern JS web app

### Testimonials

* ColocateUSA.net (2012-Current): Custom scripts for web services (billing, orders, CP) to set & reset rDNS, and CLI scripts to update forward and rDNS for IPv4 and IPv6 addresses.
* Spry/VPSlink (2007-2010): Integration with a custom control so VM clients could manage their domains and rDNS.
* Layered Tech (2005-2007): DNS management was limited to internal staff and was updated as needed. Which meant, lots of old poorly maintained data. I wrote a number of scripts for common tasks like "reset the rDNS for these IPs" or "delegate this block of IPs to these NS".
* Lightrealm/HostPro/Interland/Web.com (2000-2003): In 1999, Lightrealm's DNS was managed on Sun servers running BIND 4. DNS team members used a shared login for access and editing of the zone and named.conf files. We had 120,000 zones and reloading BIND took about 12 hours, so it was done once a day. If someone made an error, it might take 10 hours before BIND encountered it and croaked, sometimes extending the time-to-publish of DNS data to days. With the pending merger of Lightrealm, Vservers, and HostPro, our zone count was going to almost triple. We needed a better solution and found NicTool. We deployed a system that elegantly managed 400,000 zones, millions of zone records, and published changes in under a minute. NicTool remained in use at Web.com for many years thereafter.
* NDCHost.com (2003-Current): We use NicTool as the backend to our DNS infrastructure.  NicTools API allows us to easily integrate NicTool into our customer portal and allows our customers to easily add/remove/edit zones, records, and rDNS data.

### Support

* [Commercial Support](http://www.tnpi.net/cart/index.php/categories/nictool)
* [Forums](http://www.tnpi.net/support/forums/index.php/board,10.0.html)
* [Mailing Lists](https://mail.theartfarm.com/list-archives/?1)
* [Email](mailto:support@nictool.com) - Requests not accompanied by payments are handled on a "best effort" basis.
* [WIKI](https://github.com/msimerson/NicTool/wiki)
