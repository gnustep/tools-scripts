/* create-abbrevs.m - Utility to create a list of time zones and their
       associated abbreviations.

   Copyright (C) 1997 Free Software Foundation, Inc.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA
 */

#include <stdio.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSAutoreleasePool.h>
#include <Foundation/NSException.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSDate.h>
#include <Foundation/NSTimeZone.h>

int
main (int argc, char *argv[])
{
  int i;
  id pool, zone, dict, e, details, name, a;

  pool = [NSAutoreleasePool new];

  /* Load preferred abbreviation mappings.
   */
  a = [NSMutableDictionary
    dictionaryWithContentsOfFile: @"preferred_abbreviations.plist"];
  if (nil == a)
    {
      NSLog(@"Unable to load 'preferred_abbreviations.plist'");
      return 1;
    }
  for (i = 1; i < argc; i++)
    {
      name = [NSString stringWithUTF8String: argv[i]];
      zone = [NSTimeZone timeZoneWithName: name];
      if (zone != nil)
	{
	  id detail, abbrev;

	  dict = [NSMutableDictionary dictionary];
	  details = [zone timeZoneDetailArray];
	  e = [details objectEnumerator];
	  while ((detail = [e nextObject]) != nil)
	    {
	      [dict setObject: name forKey: [detail timeZoneAbbreviation]];
	    }
	  e = [dict keyEnumerator];
	  while ((abbrev = [e nextObject]) != nil)
	    {
	      printf("%s\t%s\n", [abbrev UTF8String], [name UTF8String]);
	      /* As an abbreviation can map to multiple names, and we only
	       * want a single 'default' mapping, we only add a new one if
	       * there is no existing one.
	       */
	      if (nil == [a objectForKey: abbrev])
		{
		  [a setObject: name forKey: abbrev];
		}
	    }
	}
    }
  if (NO == [a writeToFile: @"abbreviations.plist" atomically: NO])
    {
      NSLog(@"Failed to update 'abbreviations.plist'");
      return 1;
    }
  [pool release];
  return 0;
}
