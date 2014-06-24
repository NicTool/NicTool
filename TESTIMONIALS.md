### Testimonials

List yourself here! Fork [NicTool](https://github.com/msimerson/NicTool), edit [TESTIMONIALS.md](https://github.com/msimerson/NicTool/blob/master/TESTIMONIALS.md), and submit a PR.

* [Miva Merchant](http://mivamerchant.com) (2014-current)
* [ColocateUSA.net](http://www.colocateusa.net) (2012-current):
    Custom scripts for web services (billing, orders, CP) to set & reset rDNS, and CLI scripts to update forward and rDNS for IPv4 and IPv6 addresses.
* [Spry/VPSlink](http://www.spry.com) (2007-2010):
    * Integration with a custom control to manage domains and rDNS.
    * automated provisioning
    * batch processing by sysadmins
* [Layered Tech](http://www.layeredtech.com) (2005-2007): DNS management was limited to internal staff and was updated as needed. Which meant, lots of old poorly maintained data. I wrote a number of scripts for common tasks like "reset the rDNS for these IPs" or "delegate this block of IPs to these NS".
* [NDCHost](http://www.ndchost.com) (2003-current): We use NicTool as the backend to our DNS infrastructure.  NicTools API allows us to easily integrate NicTool into our customer portal and allows our customers to easily add/remove/edit zones, records, and rDNS data.
* [Lightrealm/HostPro/Interland/Web.com](http://web.com) (2000-unknown): In 1999, Lightrealm's DNS was managed on Sun servers running BIND 4. DNS team members used a shared login for access and editing of the zone and named.conf files. We had 120,000 zones and reloading BIND took about 12 hours, so it was done once a day. If someone made an error, it might take 10 hours before BIND encountered it and croaked, sometimes extending the time-to-publish of DNS data to days. With the pending merger of Lightrealm, Vservers, and HostPro, our zone count was going to almost triple. We needed a better solution and found NicTool. We deployed a system that elegantly managed 400,000 zones, millions of zone records, and published changes in under a minute. NicTool remained in use at Web.com for many years thereafter.
