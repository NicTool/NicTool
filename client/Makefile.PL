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
    'NAME'         => 'NicToolClient',
    'VERSION_FROM' => 'lib/NicToolClient.pm',
    'PREREQ_PM'    => {
        'LWP::UserAgent' => 1,
        'RPC::XML'       => 1,
        'SOAP::Lite'     => 0,
    },    # e.g., Module::Name => 1.1
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
