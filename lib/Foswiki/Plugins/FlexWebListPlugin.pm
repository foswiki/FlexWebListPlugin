# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2006-2013 Michael Daum http://michaeldaumconsulting.com
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

our $VERSION = '1.71';
our $RELEASE = '1.71';
our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'Flexible way to display hierarchical weblists';
our $core;

sub core {

  unless (defined $core) {
    require Foswiki::Plugins::FlexWebListPlugin::Core;
    $core = new Foswiki::Plugins::FlexWebListPlugin::Core;
  }

  return $core;
}

sub initPlugin {

  Foswiki::Func::registerTagHandler('FLEXWEBLIST', sub {
    return core->handler(@_);
  });

  return 1;
}

sub afterRenameHandler {
  my ($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  return if $oldTopic;
  core->reset;
}


1;
