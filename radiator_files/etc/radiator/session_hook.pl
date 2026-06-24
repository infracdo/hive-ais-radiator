sub {
    my $p = ${$_[0]};
    my $username = $p->get_attr('User-Name');
    my $csid = $p->get_attr('Called-Station-Id');

    open(my $log, '>>', '/var/log/radiator/session_debug.log');
    print $log scalar(localtime) . " - 👤 $username 📡 $csid\n";
    close($log);

    return unless $username && $csid;

    eval {
        my $dbh = DBI->connect("dbi:Pg:dbname=radius;host=localhost", "radiator", "ap0ll0ap0ll0", { RaiseError => 1, AutoCommit => 1 });
        my $sth = $dbh->prepare(q{
            INSERT INTO nas_session_mac_attrs (username, called_station_id, updated_at)
            VALUES (?, ?, NOW())
            ON CONFLICT (username)
            DO UPDATE SET called_station_id = EXCLUDED.called_station_id, updated_at = NOW()
        });
        $sth->execute($username, $csid);
        $sth->finish;
        $dbh->disconnect;

        open(my $log2, '>>', '/var/log/radiator/session_debug.log');
        print $log2 scalar(localtime) . " - ✅ INSERT OK for $username\n";
        close($log2);
    };
    if ($@) {
        open(my $errlog, '>>', '/var/log/radiator/session_debug.log');
        print $errlog scalar(localtime) . " - ❌ DB ERROR: $@\n";
        close($errlog);
    }

    return;
}
