<?php

/* Nictool API Class for Symfony framework
 * 2018-03-01 Per Abildgaard Toft (per@minfejl.dk)
 * 
 */
namespace AppBundle\Services;

use Symfony\Component\DependencyInjection\ContainerAwareInterface;
use Symfony\Component\DependencyInjection\ContainerAwareTrait;

class DnsApi implements ContainerAwareInterface
{
    
    use ContainerAwareTrait;

    private $url;

    private $location;

    private $username;

    private $password;

    private $debug = false;

    function getReverseDNS($ip)
    {
        if($this->container->getParameter("dnsapi.enabled") == false)
        {
            return;
        }
        
        
        if (! $ip)
            return;
        
        $arpa = $this->getReverseArpa($ip);
        $host = $this->getHost($ip);
        
        $options = array(
            'location' => $this->container->getParameter("dnsapi.location"),
            'uri' => $this->container->getParameter("dnsapi.uri"),
            'exceptions' => true,
            'trace' => false
        );
        $client = new \SoapClient(null, $options);
        
        $login = array(
            'username' => $this->container->getParameter("dnsapi.username"),
            'password' => $this->container->getParameter("dnsapi.password"),
            'nt_protocol_version' => '1.0'
        );
        try {
            $login = $client->login($login);
        } catch (SoapFault $fault) {
            throw $fault;
        }
        
        // Save session token
        $token = null;
        if (property_exists($login, "nt_user_session")) {
            $token = $login->nt_user_session;
        }
        unset($login);
        
        if (! $token) {
            throw new \Exception('Nictool did not return a token - login failed');
        }
        
        $group_options = array(
            'nt_group_id' => $this->container->getParameter("dnsapi.nt_group_id"),
            'include_subgroups' => 1,
            'Search' => 1,
            '1_field' => 'zone',
            '1_option' => 'equals',
            '1_value' => $arpa,
            'nt_user_session' => $token
        );
        $group = $client->get_group_zones($group_options);
        if (! $group) {
            throw new \Exception("Zone not found: $arpa");
        }
        if (property_exists($group, "total")) {
            if ($group->total != 1) {
                throw new \Exception("Zone not found: $arpa");
                // return "Zone not found: $arpa";
            }
        } else {
            throw new \Exception("Zone not found: $arpa");
            // return "Zone not found: $arpa";
        }
        // $zone = $group->zones [0]->zone;
        $zoneid = $group->zones[0]->nt_zone_id;
        // print "Success: Zone name: $zone nt_zone_id: $zoneid \n";
        
        // Search for the zone records
        $zone_options = array(
            'nt_zone_id' => $zoneid,
            'Search' => 1,
            '1_field' => 'name',
            '1_option' => 'equals',
            '1_value' => $host,
            'nt_user_session' => $token
        );
        
        $record = $client->get_zone_records($zone_options);
        
        if ($record->total > 1) {
            throw new \Exception("Multiple dns record found!");
        }
        if ($record->total == 0) {
            return;
        }
        // print "name: " . $record->records [0]->name . "\n";
        // print "address: " . $record->records [0]->address . "\n";
        return $record->records[0]->address;
    }

    function setReverseDNS($ip, $address)
    {
        
        if($this->container->getParameter("dnsapi.enabled") == false)
        {
            return;
        }
            
        // print "Set reverse $ip $address <br>\n";
        if (! $ip) {
            throw new \Exception("Missing IP address");
        }
        
        if ($this->is_valid_domain_name($address) == 0) {
            throw new \Exception("Not a valid domain name: $address");
        }
        // Append dot to the domain name
        $address = $address . ".";
        
        // Nictool Reverse Gorup ID:
        
        $arpa = $this->getReverseArpa($ip);
        $host = $this->getHost($ip);
        
        $options = array(
            'location' => $this->container->getParameter("dnsapi.location"),
            'uri' => $this->container->getParameter("dnsapi.uri"),
            'exceptions' => true,
            'trace' => false
        );
        $client = new \SoapClient(null, $options);
        
        $login = array(
            'username' => $this->container->getParameter("dnsapi.username"),
            'password' => $this->container->getParameter("dnsapi.password"),
            'nt_protocol_version' => '1.0'
        );
        
        try {
            $login = $client->login($login);
        } catch (\SoapFault $e) {
            throw new \Exception("DNS API failure! Error: " . $e->getMessage());
        }
        
        // Save session token
        $token = null;
        if (property_exists($login, "nt_user_session")) {
            $token = $login->nt_user_session;
        }
        unset($login);
        
        if (! $token) {
            throw new \Exception('Nictool did not return a token - login failed');
        }
        
        $group_options = array(
            'nt_group_id' => $this->container->getParameter("dnsapi.nt_group_id"),
            'include_subgroups' => 1,
            'Search' => 1,
            '1_field' => 'zone',
            '1_option' => 'equals',
            '1_value' => $arpa,
            'nt_user_session' => $token
        );
        $group = $client->get_group_zones($group_options);
        if (! $group) {
            throw new \Exception("Zone not found: $arpa (ip: $ip address: $address");
        }
        if (property_exists($group, "total")) {
            if ($group->total != 1) {
                throw new \Exception("Zone not found: $arpa");
                // return "Zone not found: $arpa";
            }
        } else {
            throw new \Exception("Zone not found: $arpa");
        }
        // $zone = $group->zones [0]->zone;
        $zoneid = $group->zones[0]->nt_zone_id;
        // print "Success: Zone name: $zone nt_zone_id: $zoneid \n";
        
        // Search for the zone records
        $zone_options = array(
            'nt_zone_id' => $zoneid,
            'Search' => 1,
            '1_field' => 'name',
            '1_option' => 'equals',
            '1_value' => $host,
            'nt_user_session' => $token
        );
        
        $record = $client->get_zone_records($zone_options);
        
        if ($record->total > 1) {
            throw new \Exception("Multiple dns record found!");
        }
        if ($record->total == 1) {
            
            $record->records[0]->nt_user_session = $token;
            $record->records[0]->address = $address;
            $record->records[0]->description = 'Radius ' . date("Y-m-d H:i");
            
            // dump($record->records[0]);
            $result = $client->edit_zone_record($record->records[0]);
            
            if ($result->error_code != 200) {
                throw new \Exception("Could not update DNS Zone for IP: $ip address: $address");
            }
        }
        // Record does not exists, create a new
        if (! isset($record) || $record->total == 0) {
            $new = array(
                'nt_zone_id' => $zoneid,
                'name' => $host,
                'ttl' => '84600',
                'description' => 'Radius Admin ' . date("Y-m-d H:i"),
                'type' => "PTR",
                'address' => $address,
                'nt_user_session' => $token
            );
            
            $results = $client->new_zone_record($new);
            if ($results->error_code != 200) {
                throw new \Exception("Could not create DNS Zone record for IP: $ip address: $address");
            }
        }
    }

    public function checkPrefix($ip, $mask)
    {
        $prefix = new \IPv4Block($ip, $mask);
        
        if ($mask < 24) {
            foreach ($prefix->getSubblocks('/24') as $p) {
                
                try {
                    if (! $this->checkSubnetZone($this->getReverseArpa($p->getFirstIp()))) {
                        $this->createZone($this->getReverseArpa($p->getFirstIp()));
                    }
                } catch (\Exception $ex) {
                    //dump($ex);
                    throw $ex;                    
                }
            }
        } else {
            $arpa = $this->getReverseArpa($ip);
            if (! $this->checkSubnetZone($arpa)) {
                $this->createZone($arpa);
            }
        }

    }

    public function checkSubnetZone($arpa)
    {
        if($this->container->getParameter("dnsapi.enabled") == false)
        {
            return;
        }
        
        
        $options = array(
            'location' => $this->container->getParameter("dnsapi.location"),
            'uri' => $this->container->getParameter("dnsapi.uri"),
            'exceptions' => true,
            'trace' => true
        );
        $client = new \SoapClient(null, $options);
        
        $login = array(
            'username' => $this->container->getParameter("dnsapi.username"),
            'password' => $this->container->getParameter("dnsapi.password"),
            'nt_protocol_version' => '1.0'
        );
        try {
            $login = $client->login($login);
        } catch (SoapFault $fault) {
            throw $fault;
        }
        
        // Save session token
        $token = null;
        if (property_exists($login, "nt_user_session")) {
            $token = $login->nt_user_session;
        }
        unset($login);
        
        if (! $token) {
            throw new \Exception('Nictool did not return a token - login failed');
        }
        
        $group_options = array(
            'nt_group_id' => $this->container->getParameter("dnsapi.nt_group_id"),
            'include_subgroups' => 1,
            'Search' => 1,
            '1_field' => 'zone',
            '1_option' => 'equals',
            '1_value' => $arpa,
            'nt_user_session' => $token
        );
        $group = $client->get_group_zones($group_options);
        if (! $group) {
            
            throw new ExceptionZoneNotFound();
            
            // throw new \Exception( "Zone not found: $arpa" );
        }
        if (property_exists($group, "total")) {
            if ($group->total == 1) {
                return true;
            }
            
            if ($group->total > 1) {
                throw new \Exception("Multiple DNS zones found");
            }
        }
        return false;
    }

    public function createZone($zone)
    {
        if($this->container->getParameter("dnsapi.enabled") == false)
        {
            return;
        }
        
        
        
        $options = array(
            'location' => $this->container->getParameter("dnsapi.location"),
            'uri' => $this->container->getParameter("dnsapi.uri"),
            'exceptions' => true,
            'trace' => true
        );
        $client = new \SoapClient(null, $options);
        
        $login = array(
            'username' => $this->container->getParameter("dnsapi.username"),
            'password' => $this->container->getParameter("dnsapi.password"),
            'nt_protocol_version' => '1.0'
        );
        try {
            $login = $client->login($login);
        } catch (SoapFault $fault) {
            throw $fault;
        }
        
        // Save session token
        $token = null;
        if (property_exists($login, "nt_user_session")) {
            $token = $login->nt_user_session;
        }
        
        if (! $token) {
            throw new \Exception('Nictool did not return a token - login failed');
        }
        
        $newzone_options = array(
            'nt_group_id' => $this->container->getParameter("dnsapi.nt_group_id"),
            'zone' => $zone,
            'description' => 'Radius managed zone',
            'nt_user_session' => $token
        
        );
        $ret = $client->new_zone($newzone_options);
        if (property_exists($ret, "nt_zone_id")) {
            return $ret->nt_zone_id;
        } else {
            throw new \Exception("DNS Zone $zone could not be created");
        }
    }

    // Return reverse arpa notation from IP address
    public function getReverseArpa($ip)
    {

        $rev = explode('.', $ip);
        
        $arpa = $rev[2] . "." . $rev[1] . "." . $rev[0] . ".in-addr.arpa";
        return $arpa;
    }

    // Return reverse arpa notation from IP address
    private function getHost($ip)
    {
        $rev = explode('.', $ip);
        return $rev[3];
    }

    public function generateDefaultReverse($ip)
    {
        $domain = $this->container->getParameter("dnsapi.default_domain");
        
        $ip_array = explode(".", $ip);
        return sprintf("%03d%03d%03d%03d", $ip_array[0], $ip_array[1], $ip_array[2], $ip_array[3]) . "." . $domain;
    }

    function is_valid_domain_name($domain_name)
    {
        return preg_match("/^(?!\-)(?:[a-zA-Z\d\-]{0,62}[a-zA-Z\d]\.){1,126}(?!\d+)[a-zA-Z\d]{1,63}$/", $domain_name);
    }
}

?>
