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
# Please  visit http://www.xyratex.com/contact if you need additional information or
# have any questions.
#
# GPL HEADER END
#
# Copyright 2012 Xyratex Technology Limited
#
# Author: Roman Grigoryev<Roman_Grigoryev@xyratex.com>
#

package sshprocess;
use strict;
use Test::Able;
use Test::More;
use Xperior::SshProcess;
use Log::Log4perl qw(:easy);
use Data::Dumper;
use Carp;
use IO::Socket;

use Xperior::Test;
use Xperior::SshProcess;
use Xperior::Utils;
use Xperior::Node;
$|=1;
my $sp;
my ($node, $badhostnode, $badhostnobridgenode, $stucknobridgenode);
startup         _startup  => sub {
    Log::Log4perl->easy_init($DEBUG);
    $node = Xperior::Node->new;
    $node->id('test node 1');
    $node->ip('localhost');
    $node->ctrlproto('ssh');
    $node->user('tomcat');
    $node->bridge('localhost');
    $node->bridgeuser('tomcat');

    $badhostnode = Xperior::Node->new;
    $badhostnode->id('test node 2');
    $badhostnode->ip('bad_host_name');
    $badhostnode->ctrlproto('ssh');
    $badhostnode->user('tomcat');
    $badhostnode->bridge('localhost');
    $badhostnode->bridgeuser('tomcat');

    $badhostnobridgenode = Xperior::Node->new;
    $badhostnobridgenode->id('test node 3');
    $badhostnobridgenode->ip('bad_host_name');
    $badhostnobridgenode->ctrlproto('ssh');
    $badhostnobridgenode->user('tomcat');

    $stucknobridgenode = Xperior::Node->new;
    $stucknobridgenode->id('stuck node');
    $stucknobridgenode->ip('127.0.0.1');
    $stucknobridgenode->port('7070');
    $stucknobridgenode->ctrlproto('ssh');
    $stucknobridgenode->user('tomcat');

    $node = Xperior::Node->new;
    $node->id('stuck node');
    $node->ip('127.0.0.1');
    $node->ctrlproto('ssh');
    $node->user('tomcat');

};

setup           _setup    => sub {
    $sp =  Xperior::SshProcess->new();
    $sp->init('localhost','tomcat');
};
teardown        _teardown => sub {
    $sp =undef;
};
shutdown        _shutdown => sub { };
#########################################

test plan => 3,abCreateExitCodes     => sub{

    my $res = $sp->create('sleep','/bin/sleep 30');
    is($res, 0,'Correct exit code');
    $sp->kill();
#exit 1;
    $res = $sp->create('sleep','ls /etc/passwd');
    is($res, 0,'Check result for too smal application');

    $sp->init($badhostnobridgenode);
    $res = $sp->create('sleep','/bin/sleep 30');
    is($res,-3,'Check result for bad host');


#exit 1;
};



test plan => 3, bCreateExitCodesBridge     => sub{
    $sp->init($node);
    my $res = $sp->create('sleepbr','/bin/sleep 30');
    is($res, 0,'Correct exit code for bridge case');
    $sp->kill();

    $res = $sp->create('sleepbr','ls /etc/passwd');
    is($res, 0,'Check result for too smal application for bridge case');

    $sp->init($badhostnode);
    $res = $sp->create('sleep','/bin/sleep 30');
    is($res,-3,'Check result for bad host for bridge case');

};


test plan => 1,bdMasterSocketCleanup     => sub{
    my $mastersocket;
    my $res = $sp->create('sleep','/bin/sleep 30');
    $mastersocket = $sp->controlmaster();
    $sp=undef;
    ok(not(-e $mastersocket), 'Check master socket cleanup');
};


test plan => 7, kCreateAliveKill    => sub {
    #highlevel functional test
    is($sp->killed,0, 'Check status before start');
    $sp->create('sleep','/bin/sleep 30');
    pass('App started');
    my $res = $sp->isAlive();
    is($res,0, 'Check alive for alive app');
    $sp->kill();
    $res = $sp->isAlive();
    is($res,-1, 'Check alive for exited app');
    isnt($sp->killed,0, 'Check status after kill');
    isnt($sp->exitcode,undef, 'Check 1 exit code after kill');
    isnt($sp->exitcode,0, 'Check 2 exit code after kill');

};


test plan => 4, kCreateAliveKillTimeout    => sub {

    #start only server socket accept for
    #emulating stuck node
    #
    my $sock = IO::Socket::INET->new (
        LocalHost => '127.0.0.1',
        LocalPort => '7070',
        Proto => 'tcp',
        Listen => 1,
        Reuse => 1,);
    confess "Could not create socket: $!\n"
        unless $sock;
    #test core
    $sp->defaulttimeout(5);
    my $initres  = $sp->init($stucknobridgenode);
    is($initres,-99,'Check init failure');

    $initres  = $sp->init($node);
    is($initres,0,'Check init pass');
    $sp->masterprocess->kill('SIGKILL');

    #switch to accepted port
    $sp->port(7070);
    my $res = $sp->create('sleep','/bin/sleep 30');
    #scp connect timeout, set in scp options
    is($res,-3,'Check result for stuck host, scp failed');

    my $st = $sp->_sshAsyncExec('sleep','/bin/sleep 30');
    isnt($st,0,'Check result for stuck host, _sshAsyncExec');

    #close testing server socket
    close($sock);
};


test plan => 6, lCreateAliveExit    => sub {
    #highlevel functional test
    $sp->create('sleep','/bin/sleep 15');
    pass('App started');
    is( -e $sp->pidfile, 1,'Pid file exists');
    my $res = $sp->isAlive;
    my $ec  = $sp->exitcode;
    is($res,0, 'Check alive for alive app');
    is($ec,undef, 'Check exit code for alive app');
    sleep 19;
    $res = $sp->isAlive;
    $ec  = $sp->exitcode;
    is($res, -1,  'Check alive for exited app');
    is($ec,  0, 'Check exit code for alive app');
    #exit 0;
};


test plan => 16, fRunExecution => sub {
  my $stime = time;
  my $r = $sp->run('/bin/sleep 10');
  my $etime = time;
  is($r->{exitcode},0,"Check exit code for correct run");
  is($r->{sshexitcode},0,"Check ssh exit code for correct run");
  ok($etime-$stime< 15, "Check execution time");
  $r = $sp->run('ls -la /folder/which/nobody/never/creates/');
  is($r->{exitcode},2,"Check exit code for failed run");
  $r = $sp->run('exit 255');
  is($r->{exitcode},255,"Check exit code for failed run ec 255");
  is($r->{attempts},1,"Check attempts for failed run ec 255");
  is($r->{sshexitcode},0,"Check sshexitcode for failed run ec 255");
  #exit 2;
  $stime = time;
  $r = $sp->run('/bin/sleep 60',timeout=>5);
  $etime=time;
  isnt($r->{exitcode},0,"Check exit code for timeouted run");
  isnt($sp->syncexitcode,0,"Check exit code for timeouted run #2");
  DEBUG "Execution was:".($etime-$stime);
  ok($etime-$stime < 40, "Check time of timeouted run");

  $r = $sp->run('/bin/sleep 10');
  is($r->{exitcode},0,"Check exit code for restored run");
  is($sp->syncexitcode,0,"Check exit code for restored run#2");

  my $ttycheckcmd =
  'if [ -t 1 ] ; then echo tty; else echo notty;  fi';
  $r = $sp->run($ttycheckcmd);
  is($r->{exitcode},0,"Check exit code for no tty");
  is(trim($r->{stdout}),'notty',"Check message for no tty");

  $r = $sp->run($ttycheckcmd,need_tty=>1);
  is($r->{exitcode},0,"Check exit code for tty");
  is(trim($r->{stdout}),'tty',"Check message for tty");
  #exit 1;
};

test plan => 3, fRunExecutionNegative => sub {
  $sp->init($badhostnobridgenode);
  my $r = $sp->run('echo test');
  is($r->{exitcode},-1,"Check exit code for failed run ec 255");
  is($r->{attempts},5,"Check attempts for failed run ec 255");
  is($r->{sshexitcode},255,"Check sshexitcode for failed run ec 255");
#  exit 0;
};

test plan =>4 , fRunBridgeExecution => sub {
  $sp->init($node);

  my $ttycheckcmd =
  'if [ -t 1 ] ; then echo tty; else echo notty;  fi';
  my $r = $sp->run($ttycheckcmd);
  is($r->{exitcode},0,"Check exit code for no tty");
  is(trim($r->{stdout}),'notty',"Check message for no tty");

  $r = $sp->run($ttycheckcmd,need_tty=>1);
  is($r->{exitcode},0,"Check exit code for tty");
  is(trim($r->{stdout}),'tty',"Check message for tty");

};

test plan => 12, gRunMultiCommandExecution => sub {
  my $stime = time;
  my @cmds = ('echo 12345 1>&2; echo 54321','echo qwerty','echo qazwsx');
  my $r = $sp->run(\@cmds);
  print Dumper $r;
  is($r->{exitcode}, 0, 'test run array exit code ok');
  is($r->{stderr}[0],'12345','test run array 1');
  is($r->{stderr}[1],'','test run array 2');
  is($r->{stdout}[0],'54321','test run array 3');
  is($r->{stdout}[2],'qazwsx','test run array 4');
  is(scalar(@{$r->{stdout}}),3,'test run array 5');
  is(scalar(@{$r->{stderr}}),3,'test run array 6');

  @cmds = ('echo 54321','echo qwerty; sleep 30; echo ytrewq',
                'echo qazwsx');
  $r = $sp->run(\@cmds,timeout=>5);
  is($r->{exitcode},$sp->sync_timeout_exit_code,
    "Check exit code for timeouted run array");
  isnt($r->{killed},0,"Check exit code for timeouted run array");
  is(scalar(@{$r->{stdout}}),2,'test run array timeout,1');
  is($r->{stdout}[0],'54321','test run timeout array 3');
  is($r->{stdout}[1],'qwerty','test run timeou array 4');

};

test plan => 6, fCreateSyncExecution => sub {
  my $stime = time;
  $sp->createSync('/bin/sleep 10');
  my $etime = time;
  is($sp->syncexitcode,0,"Check exit code for correct syn execution");
  ok($etime-$stime< 15, "Check execution time");
  $sp->createSync('ls -la /folder/which/nobody/never/creates/');
  is($sp->syncexitcode,2,"Check exit code for failed sync execution");

  $stime = time;
  $sp->createSync('/bin/sleep 60',5);
  $etime=time;
  isnt($sp->syncexitcode,0,"Check exit code for timeouted sync operation");
  DEBUG "Execution was:".($etime-$stime);
  ok($etime-$stime < 40, "Check time of timeouted operation");

  $sp->createSync('/bin/sleep 10');
  is($sp->syncexitcode,0,"Check exit code for restored syn operation");
};


test plan => 20,xStress    => sub {
    for(my $i=0; $i<10; $i++){
        $sp->create('sleep','/bin/sleep 10');
        my $res = $sp->isAlive;
        is($res,0, "Check alive for alive app[$i]");
        sleep 10;
        $res = $sp->isAlive;
        is($res, -1,  "Check alive for exited app[$i]");
    }
};

test plan => 10, cInit    => sub {
    is($sp->host,'localhost','host');
    is($sp->user,'tomcat','user');
    is($sp->hostname,(trim `hostname`),'Check on host hostname');
    is($sp->osversion, trim`uname -a`,'Check os version');
    my $pidfile   = $sp->pidfile;
    my $ecodefile = $sp->ecodefile;
    my $rscrfile  = $sp->rscrfile;
    $sp->init('localhost','tomcat');
    isnt($pidfile,  $sp->pidfile,'Pid file is uniq');
    isnt($ecodefile,$sp->ecodefile, 'Exit code file is uniq');
    isnt($rscrfile, $sp->rscrfile, 'Script file is uniq');
    #is($exe->getClients,1, 'Check clients after adding')

    eval{ $sp->init('localhost','tomcat');};
    is($@,'',"Connection ok");
    #negative initialization
    #eval{ $sp->init('node_on_mars','tomcat');};
    #isnt($@,''," Connection failed as expected 1");
    my $res = $sp->init('node_on_mars','tomcat');
    isnt($res,0,'Connection failed as expected 2');

    #eval{ $sp->init('localhost','ryg_on_mars');};
    #isnt($@,''," Connection failed as expected 3");
    $res = $sp->init('localhost','tomcat_om_mars');
    isnt($res,0,'Connection failed as expected 4');
};


test plan => 5, fClone    => sub {
    my $nsp = $sp->clone;
    #check that clones have same fields
    is($nsp->host,'localhost','check cloned host');
    is($nsp->user,'tomcat', 'check cloned user');
    is($nsp->osversion, trim`uname -a`,'Check cloned os version');

    #check that clones aren resf on one object
    $nsp->host('newhost');
    is($sp->host,'localhost','check org host');
    is($nsp->host,'newhost','check cloned and modified host');

};

test plan => 5, waPutFile => sub {
    my $if = '/tmp/xxxYYYzzzp';
    my $of = '/tmp/xxxYYYwwwp';
    my $nif = '/tmp/xxxYYYzzzNp';
    my $nof = '/tmp/xxxYYYwwwNp';

    DEBUG `touch $if`;
    my $res = $sp->putFile($if,$of);
    is($res,0,"Check ok result");
    ok (-e $of, "Check new file" );
    $res = $sp->putFile($nif,$nof);
    DEBUG $res;
    isnt($res,0,'Check not exist file copy');
    ok ( (! -e $nof), "Check no new file for bad source" );
    $sp->createSync('rm -f $if $of');
    is($sp->exitcode,0,"Check exit code for correct removing");
};

test plan => 5, wbPutFileBridge => sub {
    $sp->init($node);
    my $if = '/tmp/xxxYYYzzzbrr';
    my $of = '/tmp/xxxYYYwwwbrr';
    my $nif = '/tmp/xxxYYYzzzNbrr';
    my $nof = '/tmp/xxxYYYwwwNbrr';

    DEBUG `touch $if`;
    my $res = $sp->putFile($if,$of);
    is($res,0,"Check ok result  for bridge case");
    ok (-e $of, "Check new file  for bridge case" );
    $res = $sp->putFile($nif,$nof);
    DEBUG $res;
    isnt($res,0,'Check not exist file copy');
    ok ( (! -e $nof), "Check no new file for bad source for bridge case" );
    $sp->createSync('rm -f $if $of');
    is($sp->exitcode,0,"Check exit code for correct removing for bridge case");
};


test plan => 4, vaGetFile => sub {
    my $if = '/tmp/xxxYYYzzzg';
    my $of = '/tmp/xxxYYYwwwg';
    my $nif = '/tmp/xxxYYYzzzNg';
    my $nof = '/tmp/xxxYYYwwwNg';

    DEBUG `sudo rm $of `;
    DEBUG `touch $if`;
    my $res = $sp->getFile($if,$of);
    is($res,0,"Check ok result");
    ok (-e $of, "Check new file" );
    $res = $sp->getFile($nif,$nof);
    DEBUG $res;
    isnt($res,0,'Check not exist file copy');
    ok ( (! -e $nof), "Check no new file for bad source" );
    DEBUG `rm -f $if $of`;
    #exit 1;
};

test plan => 4, vbGetFileBridge => sub {
    $sp->init($node);

    my $if = '/tmp/xxxYYYzzzbr';
    my $of = '/tmp/xxxYYYwwwbr';
    my $nif = '/tmp/xxxYYYzzzNbr';
    my $nof = '/tmp/xxxYYYwwwNbr';

    DEBUG `sudo rm $of `;
    DEBUG `touch $if`;
    my $res = $sp->getFile($if,$of);
    is($res,0,"Check ok result  for bridge case");
    ok (-e $of, "Check new file  for bridge case" );


    $res = $sp->getFile($nif,$nof);
    DEBUG $res;
    isnt($res,0,'Check not exist file copy for bridge case');
    ok ( (! -e $nof), "Check no new file for bad source  for bridge case" );
    DEBUG `rm -f $if $of`;
    #exit 0;
};


#TODO add stress test and sendFile

sshprocess->run_tests;

