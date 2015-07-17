# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2015 Michael Daum http://michaeldaumconsulting.com
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

our $VERSION = '1.93';
our $RELEASE = '1.93';
our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'Flexible way to display hierarchical weblists';
our %cores = ();

sub core {

  # Item12972: get the core for this host; note there might be separate cores
  # when using VirtualHostingContrib
  my $core = $cores{$Foswiki::cfg{DefaultUrlHost}};

  unless ($core) {
    require Foswiki::Plugins::FlexWebListPlugin::Core;
    $core = $cores{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::FlexWebListPlugin::Core->new();
  }

  return $core;
}

sub initPlugin {

  Foswiki::Func::registerTagHandler('FLEXWEBLIST', sub {
    return core->handler(@_);
  });

  return 1;
}

sub finishPlugin {
  %cores = ();
}

sub afterRenameHandler {
  my ($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  return if $oldTopic;

  # SMELL: does not fire on web-creation
  core->reset;
}


1;
