# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2020 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Foswiki::Plugins::FlexWebListPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::FlexWebListPlugin::WebFilter ();

our $VERSION = '3.20';
our $RELEASE = '27 Oct 2020';

our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'Flexible way to display hierarchical weblists';
our %cores = ();
our $webList;

use constant TRACE => 0; # toggle me

# monkey-patch Func API
BEGIN {
    no warnings 'redefine';
    *Foswiki::Func::origGetListOfWebs = \&Foswiki::Func::getListOfWebs;
    *Foswiki::Func::getListOfWebs =
      \&Foswiki::Plugins::FlexWebListPlugin::getListOfWebs;
    use warnings 'redefine';
}

sub initPlugin {

  Foswiki::Func::registerTagHandler('FLEXWEBLIST', sub {
    return getCore()->handler(@_);
  });

  my $request = Foswiki::Func::getRequestObject();
  my $refresh = $request->param("refresh") || '';
  if ($refresh =~ /^(on|webs|all)$/) {
    clearCache();
  }

  return 1;
}

sub getCore() {

  # Item12972: get the core for this host; note there might be separate cores
  # when using VirtualHostingContrib

  # SMELL: why - cores are destroyed after each call???
  my $core = $cores{$Foswiki::cfg{DefaultUrlHost}};

  unless ($core) {
    require Foswiki::Plugins::FlexWebListPlugin::Core;
    $core = $cores{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::FlexWebListPlugin::Core->new();
  }

  return $core;
}

sub clearCache {

  print STDERR "called clearCache\n" if TRACE;

  undef $webList;
  my $file = Foswiki::Func::getWorkArea("FlexWebListPlugin")."/webs.txt";
  unlink $file if -e $file;
}

sub getListOfWebs {
  my ($filter, $web) = @_;

  print STDERR "called getListOfWebs(".($filter//'undef').",".($web//'undef').")\n" if TRACE;

  unless (defined $webList) {
    my $file = Foswiki::Func::getWorkArea("FlexWebListPlugin")."/webs.txt";
    print STDERR "... reading from $file\n" if TRACE;
    if (-e $file) {
      my $data = Foswiki::Func::readFile($file);
      @{$webList} = split("\n", $data) if $data;
    } 

    unless (defined $webList) {
      print STDERR "... calling store for webs\n" if TRACE;
      @{$webList} = Foswiki::Func::origGetListOfWebs();
      print STDERR "... saving to $file\n" if TRACE;
      Foswiki::Func::saveFile($file, join("\n", sort @$webList));
    }

  }

  if (defined $web) {
    $webList = [grep {/^$web[\/\.]/} @$webList];
  }

  if (defined $filter) {
    my $f = new Foswiki::Plugins::FlexWebListPlugin::WebFilter($filter);
    my $session = $Foswiki::Plugins::SESSION;
    $webList = [grep {$f->ok($session, $_)} @$webList];
  }

  print STDERR "... ".scalar(@$webList)." webs found\n" if TRACE;

  return @$webList;
}

sub updateWeb {
  my $web = shift;

  return addWeb($web) if Foswiki::Func::webExists($web);
  return removeWeb($web);
}

sub removeWeb {
  my $web = shift;

  $web = _normalizeWebName($web);
  print STDERR "called removeWeb($web)\n" if TRACE;

  my %knownWebs = map {_normalizeWebName($_) => 1} getListOfWebs();
  if ($knownWebs{$web}) {
    print STDERR "... removing web $web\n" if TRACE;
    undef $knownWebs{$web};
    saveWebList([keys %knownWebs]);
  }
}

sub addWeb {
  my $web = shift;

  $web = _normalizeWebName($web);
  print STDERR "called addWeb($web)\n" if TRACE;

  my %knownWebs = map {_normalizeWebName($_) => 1} getListOfWebs();
  unless ($knownWebs{$web}) {
    print STDERR "... adding web $web\n" if TRACE;
    $knownWebs{$web} = 1;
    saveWebList([keys %knownWebs]);
  }
}

sub saveWebList {
  my ($webs) = @_;

  return unless $webs;

  print STDERR "saveWebList(@$webs)\n" if TRACE;
  my $file = Foswiki::Func::getWorkArea("FlexWebListPlugin")."/webs.txt";
  Foswiki::Func::saveFile($file, join("\n", sort @$webs));
}


sub finishPlugin {
  %cores = ();
  $webList = undef;
}

sub afterSaveHandler {
  my ( $text, $topic, $web, $error, $meta ) = @_;

  updateWeb($web);
}

sub afterRenameHandler {
  my ($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  updateWeb($oldWeb);
  updateWeb($newWeb) if $oldWeb ne $newWeb;
}

sub _normalizeWebName {
  my $web = shift;

  $web =~ s/\//\./g;

  return $web;
}

1;
