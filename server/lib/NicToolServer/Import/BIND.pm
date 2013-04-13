package NicToolServer::Import::BIND;
# ABSTRACT: import BIND zone files into NicTool

use strict;
use warnings;

use lib 'lib';
use parent 'NicToolServer::Import::Base';

use Cwd;
use Data::Dumper;
use English;
use File::Copy;
use Params::Validate qw/ :all /;

1;

