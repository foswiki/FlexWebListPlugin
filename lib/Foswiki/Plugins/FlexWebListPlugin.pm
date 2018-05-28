# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2018 Michael Daum http://michaeldaumconsulting.com
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

our $VERSION = '2.10';
our $RELEASE = '28 May 2018';
our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'Flexible way to display hierarchical weblists';
our %cores = ();

sub initPlugin {

  Foswiki::Func::registerTagHandler('FLEXWEBLIST', sub {
    return getCore()->handler(@_);
  });

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

sub finishPlugin {
  foreach my $core (values %cores) {
    $core->reset();
  }
  %cores = ();
}

sub afterRenameHandler {
  my ($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  return if $oldTopic;

  # SMELL: does not fire on web-creation
  getCore()->reset;
}


1;
