
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


CADIR=CA
CONF=conf
SERVER_NAME=server
CLIENT_NAME=client


#######
# ALL
all: ca-certificate server-certificate client-certificate

########
# CA making
.PHONY ca-certificate: $(CADIR)/ca.crt

$(CADIR)/ca.crt: $(CADIR)/private/ca.key $(CONF)/ca.conf
	@if [ ! -f $(CADIR)/ca.crt ]; then \
		echo '*******Creating CA Certificate******'; \
		openssl req -new -x509 -days 3650 -config $(CONF)/ca.conf -key $(CADIR)/private/ca.key -out $(CADIR)/ca.crt; \
	fi

$(CADIR)/private/ca.key: supportfiles
	@if [ ! -f $(CADIR)/private/ca.key ]; then \
		echo '**********Generating CA private key********'; \
		openssl genrsa -des3 -out $(CADIR)/private/ca.key 1024 -rand /dev/urandom; \
	fi

#########
# Server Certificate making
server-certificate: $(SERVER_NAME).crt

$(SERVER_NAME).crt:  $(CADIR)/ca.crt $(CADIR)/private/ca.key $(CONF)/server-cert.conf $(SERVER_NAME).key $(SERVER_NAME).csr supportfiles
	@if [ -f $(SERVER_NAME).crt ]; then \
		echo '$(SERVER_NAME).crt already exists.'; \
		exit 1; \
	fi
	@echo '*******Signing Server Certificate*******'
	openssl ca -config $(CONF)/server-cert.conf -out $(SERVER_NAME).crt -infiles $(SERVER_NAME).csr	

$(SERVER_NAME).key:
	@if [ -f $(SERVER_NAME).key ]; then \
		echo '$(SERVER_NAME).key already exists.'; \
		exit 1; \
	fi
	@echo '*******Generating Server key********'
	openssl genrsa -out $(SERVER_NAME).key 1024
	chmod 600 $(SERVER_NAME).key

$(SERVER_NAME).csr: $(SERVER_NAME).key $(CONF)/server-req.conf
	@if [ -f $(SERVER_NAME).csr ]; then \
		echo '$(SERVER_NAME).csr already exists.'; \
		exit 1; \
	fi
	@echo '*******Creating Server Certificate Request*****'
	openssl req -new -config $(CONF)/server-req.conf -key $(SERVER_NAME).key -out $(SERVER_NAME).csr

#########
# Client Certificate making

client-certificate: $(CLIENT_NAME).crt

$(CLIENT_NAME).crt: $(CADIR)/ca.crt $(CADIR)/private/ca.key $(CONF)/client-cert.conf $(CLIENT_NAME).key $(CLIENT_NAME).csr supportfiles
	@if [ -f $(CLIENT_NAME).crt ]; then \
		echo '******$(CLIENT_NAME).crt already exists******.'; \
		exit 1; \
	fi
	@echo '******Signing Client Certificate********';
	openssl ca -config $(CONF)/client-cert.conf -out $(CLIENT_NAME).crt -infiles $(CLIENT_NAME).csr
$(CLIENT_NAME).key:
	@if [ -f $(CLIENT_NAME).key ]; then \
		echo '******$(CLIENT_NAME).key already exists******.'; \
		exit 1; \
	fi
	@echo '********Generating Client key********';
	openssl genrsa -out $(CLIENT_NAME).key 1024
	chmod 600 $(CLIENT_NAME).key
$(CLIENT_NAME).csr:
	@if [ -f $(CLIENT_NAME).csr ]; then \
		echo '******$(CLIENT_NAME).csr already exists******.'; \
		exit 1; \
	fi
	@echo '********Creating Client Certificate Request*****';
	openssl req -new -config $(CONF)/client-req.conf -key $(CLIENT_NAME).key -out $(CLIENT_NAME).csr

#########
# all misc support files
supportfiles: $(CADIR) $(CADIR)/serial $(CADIR)/index.txt $(CADIR)/private $(CADIR)/newcerts

$(CADIR):
	@if [ ! -d $(CADIR) ]; then \
		mkdir $(CADIR); \
		chmod 700 $(CADIR); \
	fi 

$(CADIR)/private: $(CADIR)
	@if [ ! -d $(CADIR)/private ]; then \
		mkdir $(CADIR)/private; \
		chmod 700 $(CADIR)/private; \
	fi 

$(CADIR)/newcerts: $(CADIR)
	@if [ ! -d $(CADIR)/newcerts ]; then \
		mkdir $(CADIR)/newcerts; \
		chmod 700 $(CADIR)/newcerts; \
	fi 

$(CADIR)/serial:
	@if [ ! -f $(CADIR)/serial ]; then \
		echo '01' > $(CADIR)/serial; \
	fi

$(CADIR)/index.txt:
	@if [ ! -f $(CADIR)/index.txt ]; then \
		touch $(CADIR)/index.txt; \
	fi
clean:
	if [ ! -d trashed ]; then \
		mkdir trashed; \
		chmod 700 trashed; \
	fi
	mv $(CADIR) trashed
	mv *.crt trashed
	mv *.csr trashed
	mv *.key trashed
	echo "All files moved to \"trashed\" directory."
