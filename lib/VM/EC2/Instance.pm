package VM::EC2::Instance;

=head1 NAME

VM::EC2::Instance - Object describing an Amazon EC2 instance

=head1 SYNOPSIS

  use VM::EC2;

  $ec2      = VM::EC2->new(...);
  $instance = $ec2->describe_instances(-instance_id=>'i-12345');

  $instanceId    = $instance->instanceId;
  $ownerId       = $instance->ownerId;
  $reservationId = $instance->reservationId;
  $imageId       = $instance->imageId;
  $state         = $instance->instanceState;
  @groups        = $instance->groups;
  $private_ip    = $instance->privateIpAddress;
  $public_ip     = $instance->ipAddress;
  $private_dns   = $instance->privateDnsName;
  $public_dns    = $instance->dnsName;
  $time          = $instance->runTime;
  $status        = $instance->current_status;
  $tags          = $instance->tags;

  $stateChange = $instance->start();
  $stateChange = $instance->stop();
  $stateChange = $instance->reboot();
  $stateChange = $instance->terminate();

=head1 DESCRIPTION

This object represents an Amazon EC2 instance, and is returned by
VM::EC2->describe_instances(). In addition to methods to query the
instance's attributes, there are methods that allow you to manage the
instance's lifecycle, including start, stopping, and terminating it.

Note that the information about security groups and reservations that
is returned by describe_instances() is copied into each instance
before returning it, so there is no concept of a "reservation set" in
this interface.

=head1 METHODS

These object methods are supported:
 
 instanceId     -- ID of this instance.

 imageId        -- ID of the image used to launch this instance.

 instanceState  -- The current state of the instance at the time
                   that describe_instances() was called, as a
                   VM::EC2::Instance::State object. Also
                   see the status() method, which re-queries EC2 for
                   the current state of the instance.

 privateDnsName -- The private DNS name assigned to the instance within
                   Amazon's EC2 network. This element is defined only
                   for running instances.

 dnsName        -- The public DNS name assigned to the instance, defined
                   only for running instances.

 reason         -- Reason for the most recent state transition, 
                   if applicable.

 keyName        -- Name of the associated key pair, if applicable.

 keyPair        -- The VM::EC2::KeyPair object, derived from the keyName

 amiLaunchIndex -- The AMI launch index, which can be used to find
                   this instance within the launch group.

 productCodes   -- A list of product codes that apply to this instance.

 instanceType   -- The instance type, such as "t1.micro". CHANGEABLE.

 launchTime     -- The time the instance launched.

 placement      -- The placement of the instance. Returns a
                   VM::EC2::Placement object.

 kernelId       -- ID of the instance's kernel. CHANGEABLE.

 ramdiskId      -- ID of the instance's RAM disk. CHANGEABLE.

 platform       -- Platform of the instance, either "windows" or empty.

 monitoring     -- State of monitoring for the instance. One of 
                   "disabled", "enabled", or "pending". CHANGEABLE:
                   pass true or "enabled" to turn on monitoring. Pass
                   false or "disabled" to turn it off.

 subnetId       -- The Amazon VPC subnet ID in which the instance is 
                   running, for Virtual Private Cloud instances only.

 vpcId          -- The Virtual Private Cloud ID for VPC instances.

 privateIpAddress -- The private (internal Amazon) IP address assigned
                   to the instance.

 ipAddress      -- The public IP address of the instance.

 sourceDestCheck -- Whether source destination checking is enabled on
                   this instance. This returns a Perl boolean rather than
                   the string "true". This method is used in conjunction
                   with VPC NAT functionality. See the Amazon VPC User
                   Guide for details. CHANGEABLE.

 groupSet       -- List of VM::EC2::Group objects indicating the VPC
                   security groups in which this instance resides. Not to be
                   confused with groups(), which returns the security groups
                   of non-VPC instances. 

 stateReason    -- A VM::EC2::Instance::State::Reason object which
                   indicates the reason for the instance's most recent
                   state change. See http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-ItemType-StateReasonType.html

 architecture   -- The architecture of the image. Either "i386" or "x86_64".

 rootDeviceType -- The type of the root device used by the instance. One of "ebs"
                   or "instance-store".

 rootDeviceName -- The name of the the device used by the instance, such as /dev/sda1.
                   CHANGEABLE.

 blockDeviceMapping -- The block device mappings for the instance, represented
                   as a list of VM::EC2::BlockDevice::Mapping objects.

 instanceLifeCycle-- "spot" if this instance is a spot instance, otherwise empty.

 spotInstanceRequestId -- The ID of the spot instance request, if applicable.

 virtualizationType -- Either "paravirtual" or "hvm".

 clientToken    -- The idempotency token provided at the time of the AMI launch,
                   if any.

 hypervisor     -- The instance's hypervisor type, either "ovm" or "xen".

 userData       -- User data passed to instance at launch. CHANGEABLE.

 disableApiTermination -- True if the instance is protected from termination
                   via the console or command-line APIs. CHANGEABLE.

 instanceInitiatedShutdownBehavior -- Action to take when the instance calls
                   shutdown or halt. One of "stop" or "terminate". CHANGEABLE.

 tagSet         -- Tags for the instance as a hashref. CHANGEABLE via add_tags()
                   and delete_tags().

The object also supports the tags() method described in
L<VM::EC2::Generic>:

 print "ready for production\n" if $image->tags->{Released};

All methods return read-only values except for those marked CHANGEABLE
in the list above. For these, you can change the instance attribute on
stopped instances by invoking the method with an appropriate new
value. For example, to change the instance type from "t1.micro" to
"m1.small", you can do this:

 my @tiny_instances = $ec2->describe_instances(-filter=>{'instance-type'=>'t1.micro'});
 for my $i (@tiny_instances) {
    next unless $i->instanceState eq 'stopped';
    $i->instanceType('m1.small') or die $ec2->error;
 }

When you attempt to change an attribute of an instance, the method
will return true on success, false on failure. On failure, the
detailed error messages can be recovered from the VM::EC2 object's
error() method.

=head1 LIFECYCLE METHODS

In addition, the following convenience functions are provided

=head2 $state = $instance->current_status

This method queries AWS for the instance's current state and returns
it as a VM::EC2::Instance::State object. This enables you to 
poll the instance until it is in the desired state:

 while ($instance->current_status eq 'pending') { sleep 5 }

=head2 $state_change = $instance->start([$wait])

This method will start the current instance and returns a
VM::EC2::Instance::State::Change object that can be used to
monitor the status of the instance. By default the method returns
immediately, but you can pass a true value as an argument in order to
pause execution until the instance is in the "running" state.

Here's a polling example:

  $state = $instance->start;
  while ($state->status eq 'pending') { sleep 5 }

Here's an example that will pause until the instance is running:

  $instance->start(1);

Attempting to start an already running instance, or one that is
in transition, will throw a fatal error.

=head2 $state_change = $instance->stop([$wait])

This method is similar to start(), except that it can be used to
stop a running instance.

=head2 $state_change = $instance->terminate([$wait])

This method is similar to start(), except that it can be used to
terminate an instance. It can only be called on instances that
are either "running" or "stopped".

=head2 $state_change = $instance->reboot()

Reboot the instance. Rebooting doesn't occur immediately; instead the
request is queued by the Amazon system and may be satisfied several
minutes later. For this reason, there is no "wait" argument.

=head2 $result = $instance->associate_address($elastic_address)

Associate an elastic address with this instance. If you are
associating a VPC elastic IP address with the instance, the result
code will indicate the associationId. Otherwise it will be a simple
perl truth value ("1") if successful, undef if false.

In the case of an ordinary EC2 Elastic IP address, the first argument may
either be an ordinary string (xx.xx.xx.xx format) or a
VM::EC2::ElasticAddress object. However, if it is a VPC elastic
IP address, then the argument must be a VM::EC2::ElasticAddress
as returned by describe_addresses(). The reason for this is that the
allocationId must be retrieved from the object in order to use in the
call.

=head2 $bool = $ec2->disassociate_address

Disassociate an elastic IP address from this instance. if any. The
result will be true if disassociation was successful. Note that for a
short period of time (up to a few minutes) after disassociation, the
instance will have no public IP address and will be unreachable from
the internet.

=head2 $instance->refresh

This method will refresh the object from AWS, updating all values to
their current ones. You can call it after starting an instance in
order to get its IP address. Note that refresh() is called
automatically for you if you call start(), stop() or terminate() with
a true $wait argument.

=head2 $text = $instance->console_output

Return the console output of the instance as a
VM::EC2::ConsoleOutput object. This object can be treated as a
string, or as an object with methods

=head2 $meta = $instance->metadata

B<For use on running EC2 instances only:> This method returns a
VM::EC2::Instance::Metadata object that will return information about
the currently running instance using the HTTP:// metadata fields
described at
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?instancedata-data-categories.html. This
is usually fastest way to get runtime information on the current
instance.

=head1 STRING OVERLOADING

When used in a string context, this object will interpolate the
instanceId.

=head1 SEE ALSO

L<VM::EC2>
L<VM::EC2::Generic>
L<VM::EC2::BlockDevice>
L<VM::EC2::State::Reason>
L<VM::EC2::State>
L<VM::EC2::Instance::Metadata>
L<VM::EC2::Tag>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut

use strict;
use base 'VM::EC2::Generic';
use VM::EC2::Group;
use VM::EC2::Instance::State;
use VM::EC2::Instance::State::Reason;
use VM::EC2::BlockDevice::Mapping;
use VM::EC2::Placement;
use MIME::Base64 qw(encode_base64 decode_base64);
use Carp 'croak';

sub new {
    my $self = shift;
    my %args = @_;
    return bless {
	data        => $args{-instance},
	reservation => $args{-reservation},
	requester   => $args{-requester},
	owner       => $args{-owner},
	groups      => $args{-groups},
	aws         => $args{-aws},
	xmlns       => $args{-xmlns},
	requestId   => $args{-requestId},
    },ref $self || $self;
}

sub reservationId {shift->{reservation} }
sub requesterId   {shift->{requester}   }
sub ownerId       {shift->{owner}       }
sub groups        {
    my $self = shift;
    my $groups = $self->{groups};
    if (@_) {
	return $self->aws->modify_instance_attribute($self,-group_id=>\@_);
    } else {
	return @$groups;
    }
}
sub group         {shift()->{groups}[0] }
sub primary_id    {shift()->instanceId  }

sub valid_fields {
    my $self  = shift;
    return qw(instanceId
              imageId
              instanceState
              privateDnsName
              dnsName
              reason
              keyName
              amiLaunchIndex
              productCodes
              instanceType
              launchTime
              placement
              kernelId
              ramdiskId
              monitoring
              privateIpAddress
              ipAddress
              sourceDestCheck
              architecture
              rootDeviceType
              rootDeviceName
              blockDeviceMapping
              instanceLifecycle
              spotInstanceRequestId
              virtualizationType
              clientToken
              hypervisor
              tagSet
             );
}

sub keyPair {
    my $self = shift;
    my $name = $self->keyName or return;
    return $self->aws->describe_key_pairs($name);
}

sub instanceState {
    my $self = shift;
    my $state = $self->SUPER::instanceState;
    return VM::EC2::Instance::State->new($state);
}

sub sourceDestCheck {
    my $self = shift;
    my $check = $self->SUPER::sourceDestCheck;
    if (@_) {
	my $c = shift() ? 'true' : 'false';
	return $self->aws->modify_instance_attribute($self,-source_dest_check=>$c);
    }
    return $check eq 'true';
}

sub groupSet {
    my $self = shift;
    my $groupSet = $self->SUPER::groupSet;
    return map {VM::EC2::Group->new($_,$self->aws,$self->xmlns,$self->requestId)}
        @{$groupSet->{item}};
}

sub placement {
    my $self = shift;
    my $p = $self->SUPER::placement or return;
    return VM::EC2::Placement->new($p,$self->aws,$self->xmlns,$self->requestId);
}

sub monitoring {
    my $self = shift;
    if (@_) {
	my $enable = shift;
	if ($enable && $enable ne 'disabled') {
	    return $self->aws->monitor_instances($self);
	} else {
	    return $self->aws->unmonitor_instances($self);
	}
    }
    return $self->SUPER::monitoring->{state};
}

sub blockDeviceMapping {
    my $self = shift;
    my $mapping = $self->SUPER::blockDeviceMapping or return;
    return map { VM::EC2::BlockDevice::Mapping->new($_,$self->aws)} @{$mapping->{item}};
}

sub stateReason {
    my $self = shift;
    my $reason = $self->SUPER::stateReason;
    return VM::EC2::Instance::State::Reason->new($reason,$self->_object_args);
}

sub kernelId {
    my $self = shift;
    my $kernel = $self->SUPER::kernelId;
    if (@_) {
	return $self->aws->modify_instance_attribute($self,-kernel=>shift());
    } else {
	return $kernel;
    }
}

sub ramdiskId {
    my $self = shift;
    my $ramdisk = $self->SUPER::ramdiskId;
    if (@_) {
	return $self->aws->modify_instance_attribute($self,-ramdisk=>shift());
    } else {
	return $ramdisk;
    }
}

sub rootDeviceName {
    my $self = shift;
    my $root = $self->SUPER::rootDeviceName;
    if (@_) {
	return $self->aws->modify_instance_attribute($self,-root_device_name => shift());
    } else {
	return $root;
    }
}

sub instanceType {
    my $self = shift;
    return $self->aws->modify_instance_attribute($self, 
						-instance_type=>shift()) if @_;
    return $self->SUPER::instanceType;
}

sub userData {
    my $self = shift;

    if (@_) {
	my $encoded = encode_base64(shift);
	return $self->aws->modify_instance_attribute($self,-user_data=>$encoded);
    }

    my $data = $self->aws->describe_instance_attribute($self,'userData') or return;
    VM::EC2::Dispatch::load_module('MIME::Base64');
    return decode_base64($data);
}

sub disableApiTermination {
    my $self = shift;
    return $self->aws->modify_instance_attribute($self, 
						-disable_api_termination=>shift()) if @_;
    return $self->aws->describe_instance_attribute($self,'disableApiTermination') eq 'true';
}

sub instanceInitiatedShutdownBehavior {
    my $self = shift;
    return $self->aws->modify_instance_attribute($self, 
						-shutdown_behavior=>shift()) if @_;
    return $self->aws->describe_instance_attribute($self,'instanceInitiatedShutdownBehavior');
}

sub current_status {
    my $self = shift;
    my ($i)  = $self->aws->describe_instances(-instance_id=>$self->instanceId);
    $i or croak "invalid instance: ",$self->instanceId;
    $self->refresh($i);
    return $i->instanceState;
}

sub status { shift->current_status } # legacy

sub start {
    my $self = shift;
    my $wait = shift;

    my $s    = $self->status;
    croak "Can't start $self: run state=$s" unless $s eq 'stopped';
    my ($i) = $self->aws->start_instances($self) or return;
    if ($wait) {
	while ($i->status eq 'pending') {
	    sleep 5;
	}
	$self->refresh;
    }
    return $i;
}

sub stop {
    my $self = shift;
    my $wait = shift;

    my $s    = $self->status;
    croak "Can't stop $self: run state=$s" unless $s eq 'running';

    my ($i) = $self->aws->stop_instances($self);
    if ($wait) {
	while ($i->status ne 'stopped') {
	    sleep 5;
	}
	$self->refresh;
    }
    return $i;
}

sub terminate {
    my $self = shift;
    my $nowait = shift;

    my $s    = $self->status;
    croak "Can't terminate $self: run state=$s"
	unless $s eq 'running' or $s eq 'stopped';

    my $i = $self->aws->terminate_instances($self) or return;
    unless ($nowait) {
	while ($i->status ne 'terminated') {
	    sleep 5;
	}
	$self->refresh;
    }
    return $i;
}

sub reboot {
    my $self = shift;

    my $s    = $self->status;
    croak "Can't reboot $self: run state=$s"unless $s eq 'running';
    return $self->aws->reboot_instances($self);
}

sub associate_address {
    my $self = shift;
    my $addr = shift or croak "Usage: \$instance->associate_address(\$elastic_address)";
    my $r = $self->aws->associate_address($addr => $self->instanceId);
    $r->{data}{ipAddress} = $addr if $r;
    return $r;
}

sub disassociate_address {
    my $self = shift;
    my $addr = $self->aws->describe_addresses(-filter=>{'instance-id'=>$self->instanceId});
    $addr or croak "Instance $self is not currently associated with an elastic IP address";
    my $r = $self->aws->disassociate_address($addr);
    delete $r->{data}{ipAddress};
    return $r;
}

sub refresh {
    my $self = shift;
    my $i   = shift;
    ($i) = $self->aws->describe_instances(-instance_id=>$self->instanceId) unless $i;
    %$self  = %$i;
}

sub console_output {
    my $self = shift;
    my $output = $self->aws->get_console_output(-instance_id=>$self->instanceId);
    return $output->output;
}

sub metadata {
    my $self = shift;
    return $self->aws->instance_metadata;
}

sub productCodes {
    my $self = shift;
    my $codes = $self->SUPER::productCodes or return;
    return map {$_->{productCode}} @{$codes->{item}};
}

1;

