use 5.005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

$|++;

my $htdocs = SetHtdocs();

my $htdocs = SetHtdocs();

sub MY::postamble {

'HTMLDIR    =   ' . $htdocs . '

web:
	install -m 0644 api.htm          $(HTMLDIR)/api/
	install -m 0644 apiindex.htm     $(HTMLDIR)/api/
	install -m 0644 apinotes.htm     $(HTMLDIR)/api/
	install -m 0644 changes.htm      $(HTMLDIR)/api/
	install -m 0644 delegationfuncs.htm $(HTMLDIR)/api/
	install -m 0644 docbook.css      $(HTMLDIR)/api/
	install -m 0644 functions.htm    $(HTMLDIR)/api/
	install -m 0644 generalfuncs.htm $(HTMLDIR)/api/
	install -m 0644 groupsfuncs.htm  $(HTMLDIR)/api/
	install -m 0644 i4866.htm        $(HTMLDIR)/api/
	install -m 0644 i7664.htm        $(HTMLDIR)/api/
	install -m 0644 index.htm        $(HTMLDIR)/api/
	install -m 0644 nameserversfuncs.htm $(HTMLDIR)/api/
	install -m 0644 objects.htm $(HTMLDIR)/api/
	install -m 0644 permissionsfuncs.htm $(HTMLDIR)/api/
	install -m 0644 typo.htm         $(HTMLDIR)/api/
	install -m 0644 usersfuncs.htm   $(HTMLDIR)/api/
	install -m 0644 zonerecordsfuncs.htm $(HTMLDIR)/api/
	install -m 0644 zonesfuncs.htm   $(HTMLDIR)/api/
	install -m 0644 img/nictool.gif  $(HTMLDIR)/api/
	install -m 0644 NicToolDocs-$(VERSION).tar.gz $(HTMLDIR)/api/NicToolDocs.tar.gz
	mv NicToolDocs-$(VERSION).tar.gz $(HTMLDIR)/api/src/
';
}

WriteMakefile(
    'NAME'		=> 'NicToolDocs',
    'VERSION_FROM'	=> 'VERSION', # finds $VERSION
    'PREREQ_PM'		=> { }, # e.g., Module::Name => 1.1
	'AUTHOR'        => 'Matt Simerson <matt@tnpi.biz>',
	'ABSTRACT'      => 'Mail::Toaster perl programs and modules',
);

sub SetHtdocs
{
	my $dir = "/Users/matt/Sites/www.nictool.com";

	unless ( -d $dir ) 
	{
		if    ( -d "/home/nictool.com/html/docs") { $dir = "/home/nictool.com/html/docs" }
		elsif ( -d "/usr/local/www/data"        ) { $dir = "/usr/local/www/data"         }
		elsif ( -d "/usr/local/www/data/mail"   ) { $dir = "/usr/local/www/data/mail"    }
		elsif ( -d "/usr/local/www/mail"        ) { $dir = "/usr/local/www/mail"         }
		elsif ( -d "/Library/Webserver/Documents" ) { $dir = "/Library/Webserver/Documents" };
	};
	return $dir;
};

