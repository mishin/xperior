#
# GPL HEADER START
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 only,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License version 2 for more details (a copy is included
# in the LICENSE file that accompanied this code).
#
# You should have received a copy of the GNU General Public License
# version 2 along with this program; If not, see http://www.gnu.org/licenses
#
# Please  visit http://www.xyratex.com/contact if you need additional
# information or have any questions.
#
# GPL HEADER END
#
# Copyright 2012 Xyratex Technology Limited
#
# Author: Roman Grigoryev<Roman_Grigoryev@xyratex.com>
#

=pod

=head1 NAME

Xperior::Executor::SingleProcessBase -
    base module for control remote execution

=head1 DESCRIPTION

This is base module for control remote execution of single process. Reused
 in several other modules which override functions.
Inherited fom L<Xperior::Executor::Base>

=head1 METHODS

=cut

package Xperior::Executor::SingleProcessBase;
use Moose;
use Data::Dumper;
use Carp qw(cluck);
use File::Path;
use Log::Log4perl qw(:easy);
use File::Copy;

use Xperior::SshProcess;
extends 'Xperior::Executor::Base';

has 'reason' => ( is => 'rw' );

=head3  execute

Function execute process on remote client and control remote execution via ssh. Only one process could be executed by one object instance. Process is executed  on first found client which marked as master.

Command line for executing  should be prepared in inheritor by defining B<_prepareCommands> function.

Before execution directory 'tempdir' from system configuration will be cleaned up.

Process executing via asynchronous call from L<Xperior::SshProcess> and use its object for regular monitoring remote process status.

When remote process not found observation stopped and execution status calculated. Status calculated by results from B<processLogs>  function, 'killed' and connection issue status, worse status selected. Also it stderr and stdout saving as test logs.

=cut


sub execute {
    my $self    = shift;
    my $mnodecfg = $self->_getMasterNode();

    #saving env data
    $self->addYE( 'masterclient', $mnodecfg);
    DEBUG "Master Node:" . Dumper $mnodecfg;
    $self->_prepareCommands;
    $self->_addCmdLogFiles;
    $self->addYE( 'cmd', $self->cmd );

    #$self->_saveStageInfoBeforeTest;

    #get remote processor
    my $mclientobj = $self->env->getNodeById( $mnodecfg->{'node'} );
    my $testproc   = $mclientobj->getRemoteConnector();
    unless ( defined($testproc) ) {
        ERROR 'Master client obj is:' . Dumper $mclientobj;
        confess "SSH to master client is undef";
    }

    ##remove and recreate directory for logs
    #TODO cleanup should be done out of sub execute
    #$testp->createSync ('rm -rf /var/log/xperior/');

    my $mountpoint = $self->env->cfg->{'client_mount_point'}
      or cluck("Undefined 'client_mount_point'");
    my @cmds = (
        'mkdir -p /var/log/xperior/',
        "mkdir -p ${mountpoint}",);

    $testproc->run(\@cmds);

    #TODO add exit value check there. Now it doesn't have value until
    #own lustre mount manager

    my $starttime = time;
    $self->addYE( 'starttime', $starttime );

    my $cr = $testproc->create( $self->appname, $self->cmd );
    if ( $cr < 0 ) {
        $self->fail(
'Cannot start or find just started remote test process on master client'
        );
        $self->addMessage(
            'Cannot start remote process, network or remote host problem.');
        $self->test->results( $self->yaml );
        $self->addYE( 'masterhostdown', 'yes' );
        $self->addYE( 'killed',         'no' );
        $self->_getLog( $testproc, $self->remote_err, 'stderr' );
        $self->_getLog( $testproc, $self->remote_out, 'stdout' );
        return;
    }

    my $endtime = $starttime + $self->test->getParam('timeout');

    my $polltime = $self->test->getParam('polltime') || $self->DEFAULT_POLL;
    DEBUG "Poll time is [$polltime]";
    while ( $endtime > time ) {

        #monitoring timeout
        sleep $polltime;
        if ( $testproc->isAlive != 0 ) {
            DEBUG "Remote app is not alive, exiting";
            last;
        }
        DEBUG "Test alive, next wait cycle";
    }
    #$testproc->createSync( 'sync', 30 );

    $self->addYE( 'endtime',         time );
    $self->addYE( 'endtime_planned', $endtime );
    ### post processing and cleanup
    my $killed     = 0;
    my $isnodedown = 0;
    my $killtime   = 0;
    my $ping       = $mclientobj->ping();
    if ( $ping and ( $testproc->isAlive == 0 ) ) {
        WARN "Test is alive after end of test execution, kill it";
        my $ts = $mclientobj->getRemoteConnector();
        DEBUG $ts->createSync('ps afx');
        DEBUG "Owned pid is:" . $testproc->pid;
        $testproc->kill;
        $killed   = 1;
        $killtime = $testproc->killed;
    }
    elsif ( not defined($ping) ) {
        $isnodedown = 1;
        $self->addMessage(
            'Incorrect master host ip or cannot resolve dns name');
    }
    elsif ( $ping == 0 ) {
        $isnodedown = 1;
        $self->addMessage('Master host is down');
    }

    $self->addYE( 'completed', 'yes' );
    DEBUG "*****After crash check:" . $testproc->exitcode;

    #$self->_saveStageInfoAfterTest;

    #cleanup tempdir after execution
    #TODO make this removing safe!!!
    $testproc->run( 'rm -rf ' . "$mountpoint/*" )
    if ($mountpoint and $mountpoint ne "");

    ### get logs

    my $getlogres = $self->_getLog( $testproc, $self->remote_err, 'stderr' );
    $getlogres = $self->_getLog( $testproc, $self->remote_out, 'stdout' );

    # processLogs return values
    my $pr = $self->NOTSET;
    if ( $getlogres == 0 ) {
        $pr = $self->processLogs( $self->getNormalizedLogName('stdout') );
    }
    else {
        $self->reason(
            "Cannot get log file [" . $self->remote_out . "]: $getlogres" );
    }

    #calculate results status
    if ( $killed > 0 ) {
        $self->addYE( 'killed',         'yes' );
        $self->addYE( 'masterhostdown', 'no' );
        my $lifetime = $killtime - $starttime;
        $self->fail("Killed by timeout after [$lifetime] sec of execution");
    }
    elsif ( $isnodedown > 0 ) {
        $self->addYE( 'masterhostdown', 'yes' );
        $self->addYE( 'killed',         'no' );
        $self->fail('Master host became down just after or while testing');
    }
    else {
        $self->addYE( 'killed',         'no' );
        $self->addYE( 'masterhostdown', 'no' );
        $self->addYE( 'exitcode',       $testproc->exitcode );
        if ( ( $testproc->exitcode == 0 ) && ( $pr == $self->PASSED ) ) {
            $self->pass;
        }
        elsif ( ( $testproc->exitcode == 0 ) && ( $pr == $self->SKIPPED ) ) {
            $self->skip( 1, $self->getReason );
        }
        elsif ( ( $testproc->exitcode != 0 ) && ( $pr == $self->PASSED ) ) {
            $self->fail(
                "Test return non-zero exit code :" . $testproc->exitcode );
        }
        else {
            $self->fail( $self->getReason );
        }
    }

    ### cleanup logs
    ### end
    #no idea what is good result there, so no return
    #$self->test->tap     ( $self->tap);
    $self->test->results( $self->yaml );

    #$self->write();
    #return $self->tap();
    $self->cleanup();
    return;
}

sub cleanup {
    my $self = shift;
}

sub getReason {
    my $self = shift;
    return $self->reason;
}

sub processSystemLog{
    my ( $self, $connector, $filename ) = @_;
    WARN 'processSystemLog is not implemented';
}

=item * _getMasterNode - retruns master node where test process will be executed

It's important to use this call for getting master node in childs. Current implementation
is Lustre-oriented but child could override it

=cut

sub _getMasterNode{
    my $self = shift;
    return $self->env->getMasterLustreClient();
}

sub _getMasterConnector{
    my $self = shift;
    my $mclient    = $self->_getMasterNode();
    my $mclientobj = $self->env->getNodeById($mclient->{'node'});
    my $connector  = $mclientobj->getRemoteConnector();
    return $connector;
}

sub _addCmdLogFiles {
    my $self = shift;
    my $r    = int rand 1000000;
    my $tee  = " | tee ";

    $self->options->{'cmdout'} = 0
      unless defined $self->options->{'cmdout'};

    $tee = " 1>  " if $self->options->{'cmdout'} == 0;
    $self->remote_err("/var/log/xperior/test_stderr.$r.log");
    $self->remote_out("/var/log/xperior/test_stdout.$r.log");
    $self->cmd( $self->cmd
          . " 2>     "
          . $self->remote_err
          . $tee
          . $self->remote_out );
    return;
}

__PACKAGE__->meta->make_immutable;
1;

=head1 COPYRIGHT AND LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License version 2 only,
as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License version 2 for more details (a copy is included
in the LICENSE file that accompanied this code).

You should have received a copy of the GNU General Public License
version 2 along with this program; If not, see http://www.gnu.org/licenses



Copyright 2012 Xyratex Technology Limited

=head1 AUTHOR

Roman Grigoryev<Roman_Grigoryev@xyratex.com>

=cut

