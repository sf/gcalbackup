#!/usr/bin/tclsh

# This should never fail since it is part of the tcl distribution
package require http

# The sha1 package is delivered with tcllib
if {[catch {package require sha1}]} {
	puts stderr "Trouble finding the sha1 package. Is tcllib installed?"
	exit 1
}

# gets set by backup proc if https needs to get imported
set needsHTTPS 0

set cals ""
proc backup {name from url} {
	global cals needsHTTPS
	if {$from ne "from"} {
		puts stderr "Error in configuration: \"$from\" should be \"from\""
		exit 1
	}
	if {[regexp {^https.*} $url]} {
		set needsHTTPS 1
	}
	lappend cals $url $name
}
	
# ~/.gcalbackup will contain the backed up calendars, so make sure it
# exists with a subdir of "storage"
file mkdir ~/.gcalbackup ~/.gcalbackup/storage ~/.gcalbackup/cals

# ~/.gcalbackup/calendars.tcl should contain the calendars to backup.
# It must set a list "cals" which contains url - name pairs.
set configfile ~/.gcalbackup/calendars.tcl
if {![file exists $configfile]} {
	set template [open $configfile w 0660]
	puts $template "# backup {CALENDAR1_NAME} from {CALENDAR1_URL}"
	puts $template "# backup {CALENDAR2_NAME} from {CALENDAR2_URL}"
	puts "Configuration file was missing."
	puts "I added a template, please enter your calendars in"
	puts "$configfile"
	exit
}
source $configfile

# support https
if {$needsHTTPS} {
	package require tls
	::http::register https 443 ::tls::socket
}

if {[llength $cals] == 0} {
	puts "No calendars defined"
	exit
}

# logging in append mode
set log [open ~/.gcalbackup/log a]

# now run the backup process for every url - name pair

foreach {url name} $cals {
    set time [clock format [clock seconds] -format %Y%m%d-%H%M]
    set httptoken [::http::geturl $url -timeout 10000]
    if {[::http::status $httptoken] ne "ok"} {
	if {[::http::status $httptoken] eq "timeout"} {
		puts $log "$time: Fail on $name with http timeout"
		puts stderr "$time: Fail on $name with http timeout"
		continue
	} else {
		puts $log "$time: Fail on $name with [::http::error $httptoken]"
		puts stderr "$time: Fail on $name with [::http::error $httptoken]"
		continue
	}
    }
    set data [::http::data $httptoken]
    # set all occurences of DTSTAMP to some standard value because of
    # caching via hash sums
    regsub -all -line {^DTSTAMP:.*$} $data {DTSTAMP: 20080101T000000Z} data
    set hash [::sha1::sha1 $data]
    set store ~/.gcalbackup/storage/$hash
    if {![file exist $store]} {
	set out [open $store w 0660]
	puts $out $data
	puts $log "$time: New file stored in $hash"
    } else {
	puts $log "$time: $name did not change"
	continue
    }
    set linkname ~/.gcalbackup/cals/$name-$time.ics
    if {![file exist $linkname]} {
	puts $log "$time: Link $linkname to $hash"
	file link $linkname $store
    } else {
	puts $log "$time: Fail on $name. Link already exists."
    }
}
