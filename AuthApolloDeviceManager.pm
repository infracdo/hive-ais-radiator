
# AuthApolloDeviceManager.pm
#
# Object for handling Authentication and accounting by SQL
#
# Author: Marc Clemen Andres (mcandres888@gmail.com)
# Copyright (C) 2025
# $Id$

package Radius::AuthApolloDeviceManager;
@ISA = qw(Radius::AuthGeneric Radius::SqlDb Radius::AuthSQL);
use Radius::AuthGeneric;
use Radius::AuthSQL;
use Radius::SqlDb;
use DBI;
use strict;
use JSON;

%Radius::AuthApolloDeviceManger::ConfigKeywords = ();
# RCS version number of this module
$Radius::AuthApolloDeviceManager::VERSION = '$Revision$';
#####################################################################

#####################################################################
# Do per-instance configuration check
# This is called by Configurable just before activate
sub check_config
{
    my ($self) = @_;

    $self->Radius::AuthGeneric::check_config();
    $self->Radius::SqlDb::check_config();
    return;
}

#####################################################################
sub activate
{
    my ($self) = @_;

    $self->Radius::AuthGeneric::activate;
    $self->Radius::SqlDb::activate;

    return;
}

#####################################################################
# Do per-instance default initialization
# This is called by Configurabel during Configurable::new before
# the config file is parsed. Its a good place initalze 
# instance variables
# that might get overridden when the config file is parsed.
sub initialize
{
    my ($self) = @_;

    $self->Radius::AuthGeneric::initialize;
    $self->Radius::SqlDb::initialize;

    $self->{NullPasswordMatchesAny} = 1;
    $self->log($main::LOG_DEBUG, "[AuthApolloDeviceManger] Initialized");
    return;
}


#####################################################################
# Handle a request
# This function is called for each packet. $p points to a Radius::
# packet
# REVISIT:should we fork before handling. There might be long timeouts?
sub handle_request
{
    my ($self, $p, $dummy, $extra_checks) = @_;

    return ($main::IGNORE, "Ignored due to IgnoreAccounting")
	if $self->{IgnoreAccounting} 
           && $p->code eq 'Accounting-Request';

    if ($p->code eq 'Access-Request' || $self->{AuthenticateAccounting})
    {
	# The default behaviour in AuthGeneric is fine for this
	return $self->SUPER::handle_request($p, $p->{rp}, $extra_checks);
    }
    elsif ($p->code eq 'Accounting-Request')
    {
	# TODO: for accounting since this is based on AuthSQL you can still use the same accounting setup
    	$self->log($main::LOG_DEBUG, "[ZEEP] RequestType = Accounting-Request", $p);
	$self->handle_accounting_apollo($p);

	# Short circuits for no accounting
	return ($main::ACCEPT, 'Accounting not stored')
	    if (!defined $self->{AcctColumnDef} 
		|| $self->{AccountingTable} eq '')
		&& !defined $self->{AcctSQLStatement};

	my $status_type = $p->getAttrByNum($Radius::Radius::ACCT_STATUS_TYPE);
	# If we have a HandleAcctStatusTypes and this type is not mentioned
	# Acknowledge it, but dont do anything else with it
	return ($main::ACCEPT, 'Accepted due to HandleAcctStatusTypes')
	    if defined $self->{HandleAcctStatusTypes}
	       && !exists $self->{HandleAcctStatusTypes}{$status_type};

	# REVISIT: remove support for AccountingStartsOnly
	# AccountingStopsOnly, and AccountingAlivesOnly in the future.
	# If AccountingStartsOnly is set, only process Starts
	# Acknowledge and drop anything else
	return ($main::ACCEPT, 'Accepted due to AccountingStartsOnly')
	    if $self->{AccountingStartsOnly}
	       && $status_type ne 'Start';
	
	# If AccountingStopsOnly is set, only process Stops
	# Acknowledge and drop anything else
	return ($main::ACCEPT, 'Accepted due to AccountingStopsOnly')
	    if $self->{AccountingStopsOnly}
	       && $status_type ne 'Stop';

	# If AccountingAlivesOnly is set, only process Alives
	# Acknowledge and drop anything else
	return ($main::ACCEPT, 'Accepted due to AccountingAlivesOnly')
	    if $self->{AccountingAlivesOnly}
	       && $status_type ne 'Alive';

	return $self->handle_accounting($p);
    }
    else
    {
	# Send a generic reply on our behalf
	return ($main::ACCEPT, 'Not a relevant request type');
    }
}

sub findUser
{
    my ($self, $name, $p) = @_;
    my $user;

    # (Re)-connect to the database if necessary, 
    return (undef, 1) unless $self->reconnect;

    my ($original_user_name, $sth);
    
    $user = Radius::User->new($name);
    my $qname = $self->quote($name);
    $self->log($main::LOG_DEBUG, "[ADM]!!!!!!!!!!!!user: $user $qname $original_user_name ", $p);

    # Query the database to get user attributes
    # Based on app/models/__init__.py PPPoEUser model
    my $query = qq{
        SELECT 
            user_name,
            user_password,
            nas_ip_address,
            service_type,
            framed_protocol,
            framed_ip_address,
            framed_ip_netmask,
            framed_pool,
            mikrotik_rate_limit,
            mikrotik_address_list,
            mikrotik_group,
            mikrotik_recv_limit_gigawords,
            mikrotik_xmit_limit_gigawords,
	    is_active,
            is_overdue
        FROM pppoe_users
        WHERE user_name = $qname
          AND is_active = true
        LIMIT 1
    };
    
    $self->log($main::LOG_DEBUG, "[ADM] Executing query: $query", $p);
    
    $sth = $self->prepareAndExecute($query);
    if (!$sth)
    {
        $self->log($main::LOG_ERR, "[ADM] Failed to execute query for user $name", $p);
        return (undef, 1);
    }
    
    # Fetch the user data
    my $row = $sth->fetchrow_hashref();
    $sth->finish();
    
    if (!$row)
    {
        $self->log($main::LOG_INFO, "[ADM] User $name not found in pppoe_users table", $p);
        return (undef, 0);
    }
    
    $self->log($main::LOG_INFO, "[ADM] Found user $name in database", $p);
    
    # Set CHECK attributes (for authentication)
    if ($row->{user_password})
    {
        $user->get_check->add_attr('User-Password', $row->{user_password});
        $self->log($main::LOG_DEBUG, "[ADM] Set User-Password for $name", $p);
    }
    
    # Set REPLY attributes (returned to NAS after successful authentication)
    
    # # Service Type (e.g., Framed-User)
    # if ($row->{service_type})
    # {
    #     $user->get_reply->add_attr('Service-Type', $row->{service_type});
    #     $self->log($main::LOG_DEBUG, "[ADM] Set Service-Type: $row->{service_type}", $p);
    # }
    
    # # Framed Protocol (e.g., PPP)
    # if ($row->{framed_protocol})
    # {
    #     $user->get_reply->add_attr('Framed-Protocol', $row->{framed_protocol});
    #     $self->log($main::LOG_DEBUG, "[ADM] Set Framed-Protocol: $row->{framed_protocol}", $p);
    # }
    

    # Framed IP Address (static IP for user)
    # IMPORTANT: Skip if user is overdue - let MikroTik profile assign IP from overdue pool
    if ($row->{framed_ip_address} && !$row->{is_overdue})
    {
        $user->get_reply->add_attr('Framed-IP-Address', $row->{framed_ip_address});
        $self->log($main::LOG_DEBUG, "[ADM] Set Framed-IP-Address: $row->{framed_ip_address}", $p);
    }
    elsif ($row->{is_overdue} && $row->{framed_ip_address})
    {
        $self->log($main::LOG_INFO, "[ADM] Skipping Framed-IP-Address for overdue user (captive portal will assign)", $p);
    }

    # Framed IP Netmask
    # IMPORTANT: Skip if user is overdue - let MikroTik profile assign netmask
    if ($row->{framed_ip_netmask} && !$row->{is_overdue})
    {
        $user->get_reply->add_attr('Framed-IP-Netmask', $row->{framed_ip_netmask});
        $self->log($main::LOG_DEBUG, "[ADM] Set Framed-IP-Netmask: $row->{framed_ip_netmask}", $p);
    }
    elsif ($row->{is_overdue} && $row->{framed_ip_netmask})
    {
        $self->log($main::LOG_INFO, "[ADM] Skipping Framed-IP-Netmask for overdue user (captive portal will assign)", $p);
    }

    # Framed Pool (IP pool name)
    # IMPORTANT: Skip if user is overdue - let MikroTik "overdue" profile assign from overdue-pool
    if ($row->{framed_pool} && !$row->{is_overdue})
    {
        $user->get_reply->add_attr('Framed-Pool', $row->{framed_pool});
        $self->log($main::LOG_DEBUG, "[ADM] Set Framed-Pool: $row->{framed_pool}", $p);
    }
    elsif ($row->{is_overdue} && $row->{framed_pool})
    {
        $self->log($main::LOG_INFO, "[ADM] Skipping Framed-Pool for overdue user (overdue profile will use overdue-pool)", $p);
    }

    
    # Mikrotik Rate Limit (bandwidth control)
    if ($row->{mikrotik_rate_limit})
    {
        $user->get_reply->add_attr('Mikrotik-Rate-Limit', $row->{mikrotik_rate_limit});
        $self->log($main::LOG_DEBUG, "[ADM] Set Mikrotik-Rate-Limit: $row->{mikrotik_rate_limit}", $p);
    }
    
    # Mikrotik Address List (firewall group)
    if ($row->{mikrotik_address_list})
    {
        $user->get_reply->add_attr('Mikrotik-Address-List', $row->{mikrotik_address_list});
        $self->log($main::LOG_DEBUG, "[ADM] Set Mikrotik-Address-List: $row->{mikrotik_address_list}", $p);
    }
    


    # IMPORTANT: If user is overdue, force group to "overdue" for captive portal redirect
    if ($row->{is_overdue})
    {
        $user->get_reply->add_attr('Mikrotik-Group', 'overdue');
        $self->log($main::LOG_INFO, "[ADM] User is OVERDUE - Set Mikrotik-Group: overdue (captive portal)", $p);
    }
    elsif ($row->{mikrotik_group})
    {
        $user->get_reply->add_attr('Mikrotik-Group', $row->{mikrotik_group});
        $self->log($main::LOG_DEBUG, "[ADM] Set Mikrotik-Group: $row->{mikrotik_group}", $p);
    }




    
    # Mikrotik Recv Limit Gigawords (download quota in GB)
    if (defined $row->{mikrotik_recv_limit_gigawords})
    {
        $user->get_reply->add_attr('Mikrotik-Recv-Limit-Gigawords', $row->{mikrotik_recv_limit_gigawords});
        $self->log($main::LOG_DEBUG, "[ADM] Set Mikrotik-Recv-Limit-Gigawords: $row->{mikrotik_recv_limit_gigawords}", $p);
    }
    
    # Mikrotik Xmit Limit Gigawords (upload quota in GB)
    if (defined $row->{mikrotik_xmit_limit_gigawords})
    {
        $user->get_reply->add_attr('Mikrotik-Xmit-Limit-Gigawords', $row->{mikrotik_xmit_limit_gigawords});
        $self->log($main::LOG_DEBUG, "[ADM] Set Mikrotik-Xmit-Limit-Gigawords: $row->{mikrotik_xmit_limit_gigawords}", $p);
    }
    
    # Add Session-Timeout if needed (optional - you can make this configurable)
    # Uncomment the line below if you want to add session timeout
    # $user->get_reply->add_attr('Session-Timeout', 3600);
    
    $self->log($main::LOG_INFO, "[ADM] Successfully loaded attributes for user $name from database", $p);
   
    return $user;
}


#####################################################################
# Handle an accounting request
# Inserts accounting data into pppoe_accounting_requests table
sub handle_accounting_apollo
{
    my ($self, $p) = @_;

    # (Re)-connect to the database if necessary
    return ($main::REJECT, 'Database connection failed')
        unless $self->reconnect;

    $self->log($main::LOG_DEBUG, "[ADM] Processing accounting request", $p);

    # Extract RADIUS attributes from the packet
    my $service_type = $p->getAttrByNum($Radius::Radius::SERVICE_TYPE);
    my $framed_protocol = $p->getAttrByNum($Radius::Radius::FRAMED_PROTOCOL);
    my $nas_port = $p->getAttrByNum($Radius::Radius::NAS_PORT);
    my $nas_port_type = $p->getAttrByNum($Radius::Radius::NAS_PORT_TYPE);
    my $user_name = $p->getAttrByNum($Radius::Radius::USER_NAME);
    my $calling_station_id = $p->getAttrByNum($Radius::Radius::CALLING_STATION_ID);
    my $called_station_id = $p->getAttrByNum($Radius::Radius::CALLED_STATION_ID);
    my $nas_port_id = $p->getAttrByNum($Radius::Radius::NAS_PORT_ID);
    my $acct_session_id = $p->getAttrByNum($Radius::Radius::ACCT_SESSION_ID);
    my $framed_ip_address = $p->getAttrByNum($Radius::Radius::FRAMED_IP_ADDRESS);
    my $acct_authentic = $p->getAttrByNum($Radius::Radius::ACCT_AUTHENTIC);
    my $event_timestamp = $p->getAttrByNum($Radius::Radius::EVENT_TIMESTAMP);
    my $acct_status_type = $p->getAttrByNum($Radius::Radius::ACCT_STATUS_TYPE);
    my $nas_identifier = $p->getAttrByNum($Radius::Radius::NAS_IDENTIFIER);
    my $acct_delay_time = $p->getAttrByNum($Radius::Radius::ACCT_DELAY_TIME);
    my $nas_ip_address = $p->getAttrByNum($Radius::Radius::NAS_IP_ADDRESS);

    # Validate required fields
    if (!$user_name || !$acct_session_id || !$nas_ip_address)
    {
        $self->log($main::LOG_ERR, "[ADM] Missing required accounting fields: user_name, acct_session_id, or nas_ip_address", $p);
        return ($main::REJECT, 'Missing required accounting fields');
    }

    $self->log($main::LOG_DEBUG, "[ADM] Accounting for user: $user_name, session: $acct_session_id, status: $acct_status_type", $p);

    # Quote values for SQL safety
    my $q_service_type = $self->quote($service_type);
    my $q_framed_protocol = $self->quote($framed_protocol);
    my $q_nas_port = defined($nas_port) ? $nas_port : 'NULL';
    my $q_nas_port_type = $self->quote($nas_port_type);
    my $q_user_name = $self->quote($user_name);
    my $q_calling_station_id = $self->quote($calling_station_id);
    my $q_called_station_id = $self->quote($called_station_id);
    my $q_nas_port_id = $self->quote($nas_port_id);
    my $q_acct_session_id = $self->quote($acct_session_id);
    my $q_framed_ip_address = $self->quote($framed_ip_address);
    my $q_acct_authentic = $self->quote($acct_authentic);
    my $q_event_timestamp = defined($event_timestamp) ? $event_timestamp : 'NULL';
    my $q_acct_status_type = $self->quote($acct_status_type);
    my $q_nas_identifier = $self->quote($nas_identifier);
    my $q_acct_delay_time = defined($acct_delay_time) ? $acct_delay_time : 'NULL';
    my $q_nas_ip_address = $self->quote($nas_ip_address);

    # Build INSERT query with ON CONFLICT UPDATE for PostgreSQL
    # This will insert new records or update existing ones based on unique key
    my $query = qq{
        INSERT INTO pppoe_accounting_requests (
            service_type,
            framed_protocol,
            nas_port,
            nas_port_type,
            user_name,
            calling_station_id,
            called_station_id,
            nas_port_id,
            acct_session_id,
            framed_ip_address,
            acct_authentic,
            event_timestamp,
            acct_status_type,
            nas_identifier,
            acct_delay_time,
            nas_ip_address,
            created_at,
            updated_at
        ) VALUES (
            $q_service_type,
            $q_framed_protocol,
            $q_nas_port,
            $q_nas_port_type,
            $q_user_name,
            $q_calling_station_id,
            $q_called_station_id,
            $q_nas_port_id,
            $q_acct_session_id,
            $q_framed_ip_address,
            $q_acct_authentic,
            $q_event_timestamp,
            $q_acct_status_type,
            $q_nas_identifier,
            $q_acct_delay_time,
            $q_nas_ip_address,
            NOW(),
            NOW()
        )
        ON CONFLICT (acct_session_id, acct_status_type)
        DO UPDATE SET
            service_type = EXCLUDED.service_type,
            framed_protocol = EXCLUDED.framed_protocol,
            nas_port = EXCLUDED.nas_port,
            nas_port_type = EXCLUDED.nas_port_type,
            user_name = EXCLUDED.user_name,
            calling_station_id = EXCLUDED.calling_station_id,
            called_station_id = EXCLUDED.called_station_id,
            nas_port_id = EXCLUDED.nas_port_id,
            framed_ip_address = EXCLUDED.framed_ip_address,
            acct_authentic = EXCLUDED.acct_authentic,
            event_timestamp = EXCLUDED.event_timestamp,
            nas_identifier = EXCLUDED.nas_identifier,
            acct_delay_time = EXCLUDED.acct_delay_time,
            nas_ip_address = EXCLUDED.nas_ip_address,
            updated_at = NOW()
    };

    $self->log($main::LOG_DEBUG, "[ADM] Executing accounting insert/update query", $p);

    # Execute the query
    my $sth = $self->prepareAndExecute($query);
    if (!$sth)
    {
        $self->log($main::LOG_ERR, "[ADM] Failed to insert/update accounting record for user $user_name", $p);
        return ($main::REJECT, 'Failed to store accounting record');
    }

    $sth->finish();
    $self->log($main::LOG_INFO, "[ADM] Successfully stored accounting record for user $user_name, session $acct_session_id, status $acct_status_type", $p);

    return ($main::ACCEPT, 'Accounting record stored');
}



1;


