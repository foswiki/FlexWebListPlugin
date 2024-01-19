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

package Foswiki::Plugins::FlexWebListPlugin::WebFilter;

use strict;
use warnings;
use Foswiki::WebFilter ();

our @ISA = ('Foswiki::WebFilter');

sub new {
  my ($class, $filter) = @_;

  my $this = bless({}, $class);

  foreach my $f (qw(user template public allowed sitemap)) {
    $this->{$f} = ($filter =~ /\b$f\b/);
  }

  return $this;
}

sub ok {
  my ($this, $session, $web) = @_;

  return 0 if $this->{template} && $web !~ /(?:^_|\/_)/;

  return 1 if ($web eq $session->{webName});

  return 0 if $this->{user} && $web =~ /(?:^_|\/_)/;

  # disabled for performance reasons
  #return 0 if !$session->webExists($web);

  my $webObject = Foswiki::Meta->new($session, $web);

  # disabled for performance reasons
  #my $thisWebNoSearchAll = Foswiki::isTrue($webObject->getPreference('NOSEARCHALL'), 0);
  #my $thisWebSiteMapList = Foswiki::isTrue($webObject->getPreference('SITEMAPLIST'), 1);

  #return 0
  #  if ($this->{public} && $thisWebNoSearchAll) ||
  #     ($this->{sitemap} && !$thisWebSiteMapList);

  return 0 if $this->{allowed} && !$webObject->haveAccess('VIEW');

  return 1;
}

1;
