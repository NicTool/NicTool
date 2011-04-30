use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
#
# NicTool v2.00-rc1 Copyright 2001 Damon Edwards, Abe Shelton & Greg Schueler
# NicTool v2.01 Copyright 2004 The Network People, Inc.
#
# NicTool is free software; you can redistribute it and/or modify it under
# the terms of the Affero General Public License as published by Affero,
# Inc.; either version 1 of the License, or any later version.
#
# NicTool is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the Affero GPL for details.
#
# You should have received a copy of the Affero General Public License
# along with this program; if not, write to Affero Inc., 521 Third St,
# Suite 225, San Francisco, CA 94107, USA
#

WriteMakefile(
    'NAME'         => 'NicToolServer',
    'VERSION_FROM' => 'NicToolServer.pm',
    'PREREQ_PM'    => {
        'DBI'                => 1.20,
        'DBD::mysql'         => 2.0416,
        'SOAP::Lite'         => 0.51,
        'Net::IP'            => 0,
        'Apache2::SOAP'      => 0,
        'Apache::DBI'        => 0,
        'XML::Parser'        => 0,
        'Digest::MD5'        => 0,
        'Digest::HMAC'       => 0,
    },
    'LICENSE'      => 'affero-gpl',
    'ABSTRACT'     => 'DNS management solution',
    'AUTHOR'       => 'Damon Edwards, Abe Shelton, Greg Schueler, Matt Simerson',
);

sub MY::postamble {
'
deps:
	perl bin/install_deps.pl
';
};
