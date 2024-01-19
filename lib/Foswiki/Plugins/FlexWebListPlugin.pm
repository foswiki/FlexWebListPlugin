# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2024 Michael Daum http://michaeldaumconsulting.com
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
use Foswiki::Plugins::FlexWebListPlugin::WebFilter ();

our $VERSION = '4.20';
our $RELEASE = '%$RELEASE%';

our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'Flexible way to display hierarchical weblists';
our $LICENSECODE = '%$LICENSECODE%';
our %cores = ();

use constant MEMORYCACHE => 1;
use constant TRACE => 0; # toggle me

# monkey-patch Func API
BEGIN {
    no warnings 'redefine'; ## no critic
    *Foswiki::Func::origGetListOfWebs = \&Foswiki::Func::getListOfWebs;
    *Foswiki::Func::getListOfWebs = sub { return getCore()->getListOfWebs(@_);};
    use warnings 'redefine';
}

sub initPlugin {
  my ($topic, $web) = @_;

  Foswiki::Func::registerTagHandler('FLEXWEBLIST', sub {
    return getCore()->handleFLEXWEBLIST(@_);
  });

  my $request = Foswiki::Func::getRequestObject();
  my $refresh = $request->param("refresh") || '';
  if ($refresh =~ /^(on|webs|all)$/) {
    getCore()->clearCache();
    getCore()->readWebList();
  }

  return 1;
}

sub finishPlugin {

  foreach my $core (values %cores) {
    $core->finish();
  }

  %cores = () unless MEMORYCACHE;
}

sub getCore {

  my $core = $cores{$Foswiki::cfg{DefaultUrlHost}};

  unless ($core) {
    require Foswiki::Plugins::FlexWebListPlugin::Core;
    $core = $cores{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::FlexWebListPlugin::Core->new();
  }

  return $core;
}

sub afterSaveHandler {
  my ($text, $topic, $web, $error, $meta) = @_;

  _writeDebug("called afterSaveHandler($web)");
  getCore()->updateWeb($web);
}

sub afterRenameHandler {
  my ($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  _writeDebug("called afterRenameHandler(oldWeb=$oldWeb, newWeb=$newWeb)");
  getCore()->updateWeb($oldWeb);
  getCore()->updateWeb($newWeb) if $oldWeb ne $newWeb;
}

sub _writeDebug {
  print STDERR '- FlexWebListPlugin - '.$_[0]."\n" if TRACE;
}


1;
