package VM::EC2;

=head1 NAME

VM::EC2 - Control the Amazon EC2 and Eucalyptus Clouds

=head1 SYNOPSIS

 # set environment variables EC2_ACCESS_KEY, EC2_SECRET_KEY and/or EC2_URL
 # to fill in arguments automatically

 my $ec2 = VM::EC2->new(-access_key => 'access key id',
                      -secret_key => 'aws_secret_key',
                      -endpoint   => 'http://ec2.us-east-1.amazonaws.com');

 my ($image) = $ec2->describe_images(-image_id=>'ami-12345');

 $image->run_instances(-key_name      =>'My_key',
                       -security_group=>'default',
                       -min_count=>2,
                       -instance_type => 't1.micro'

 my @snapshots = $ec2->describe_snapshots(-snapshot_id => 'id',
                                          -owner         => 'ownerid',
                                          -restorable_by => 'userid',
                                          -filter        => {'tag:Name'=>'Root',
                                                              'tag:Role'=>'Server'});

 foreach (@snapshots) { $_->add_tags('Version'=>'1.0') }

 my @instances = $ec2->describe_instances(-instance_id => 'id',
                                          -filter      => {architecture=>'i386',
                                                           'tag:Role'=>'Server'});
 my @volumes = $ec2->describe_volumes(-volume_id => 'id',
                                      -filter    => {'tag:Role'=>'Server'});

=head1 DESCRIPTION

This is a partial interface to the 2011-05-15 version of the Amazon
AWS API. It was written provide access to the new tag and metadata
interface that is not currently supported by Net::Amazon::EC2, as well
as to provide developers with an extension mechanism for the API.

The main interface is the VM::EC2 object, which provides methods for
interrogating the Amazon EC2, launching instances, and managing
instance lifecycle. These methods return the following major object
classes which act as specialized interfaces to AWS:

 VM::EC2::BlockDevice               -- A block device
 VM::EC2::BlockDevice::Attachment   -- Attachment of a block device to an EC2 instance
 VM::EC2::BlockDevice::EBS          -- An elastic block device
 VM::EC2::BlockDevice::Mapping      -- Mapping of a virtual storage device to a block device
 VM::EC2::BlockDevice::Mapping::EBS -- Mapping of a virtual storage device to an EBS block device
 VM::EC2::Group                     -- Security groups
 VM::EC2::Image                     -- Amazon Machine Images (AMIs)
 VM::EC2::Instance                  -- Virtual machine instances
 VM::EC2::Instance::Metadata        -- Access to runtime metadata from running instances
 VM::EC2::Region                    -- Availability regions
 VM::EC2::Snapshot                  -- EBS snapshots
 VM::EC2::Tag                       -- Metadata tags

In addition, there are several utility classes:

 VM::EC2::Generic                   -- Base class for all AWS objects
 VM::EC2::Error                     -- Error messages
 VM::EC2::Dispatch                  -- Maps AWS XML responses onto perl object classes
 VM::EC2::ReservationSet            -- Hidden class used for describe_instances() request;
                                               The reservation Ids are copied into the Instance
                                               object.

The AWS API is identical to that described at http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/
with the following differences:

 1) For consistency with Perl standards, method names are in
    lowercase and words in long method names are separated
    with underscores. The Amazon API prefers mixed case. 
    So in the Amazon API the call to fetch instance information
    is "DescribeInstances", while in VM::EC2, the method is
    describe_instances(). To avoid annoyance, if you use the mixed
    case form for a method name, the Perl autoloader will
    automatically translate it to underscores for you, so you can
    call either $ec2->describe_instances() or
    $ec2->DescribeInstances().

 2) Named arguments passed to methods are all lowercase, use
    underscores to separate words and start with hyphens.
    In other words, if the AWS API calls for an argument named
    "InstanceId" to be passed to the "DescribeInstances" call, then
    the corresponding Perl function will look like:

         $instance = $ec2->describe_instances(-instance_id=>'i-12345')

    In a small number of cases, when the parameter name was absurdly
    long, it has been abbreviated. For example, the
    "Placement.AvailabilityZone" parameter has been represented as
    -placement_zone and not -placement_availability_zone. See the
    documentation for these cases.

 3) For each of the describe_foo() methods (where "foo" is a type of
    resource such as "instance"), you can fetch the resource by using
    their IDs either with the long form:

          $ec2->describe_foo(-foo_id=>['a','b','c']),

    or a shortcut form: 

          $ec2->describe_foo('a','b','c');

 4) When the API calls for a list of arguments named Arg.1, Arg.2,
    then the Perl interface allows you to use an anonymous array for
    the consecutive values. For example to call describe_instances()
    with multiple instance IDs, use:

       @i = $ec2->describe_instances(-instance_id=>['i-12345','i-87654'])

 5) All Filter arguments are represented as a -filter argument whose value is
    an anonymous hash:

       @i = $ec2->describe_instances(-filter=>{architecture=>'i386',
                                               'tag:Name'  =>'WebServer'})

    When adding or removing tags, the -tag argument has the same syntax.

 6) The tagnames of each XML object returned from AWS are converted into methods
    with the same name and typography. So the <privateIpAddress> tag in a
    DescribeInstancesResponse, becomes:

           $instance->privateIpAddress

    You can also use the more Perlish form -- this is equivalent:

          $instance->private_ip_address

    Methods that correspond to complex objects in the XML hierarchy
    return the appropriate Perl object. For example, an instance's
    blockDeviceMapping() method returns an object of type
    VM::EC2::BlockDevice::Mapping.

    All objects have a fields() method that will return the XML
    tagnames listed in the AWS specifications.

      @fields = sort $instance->fields;
      # 'amiLaunchIndex', 'architecture', 'blockDeviceMapping', ...

 7) Whenever an object has a unique ID, string overloading is used so that 
    the object interpolates the ID into the string. For example, when you
    print a VM::EC2::Volume object, or use it in another string context,
    then it will appear as the string "vol-123456". Nevertheless, it will
    continue to be usable for method calls.

         ($v) = $ec2->describe_volumes();
         print $v,"\n";                 # prints as "vol-123456"
         $zone = $v->availabilityZone;  # acts like an object

 8) Many objects have convenience methods that invoke the AWS API on your
    behalf. For example, instance objects have a current_status() method that returns
    the run status of the object, as well as start(), stop() and terminate()
    methods that control the instance's lifecycle.

         if ($instance->current_status eq 'running') {
             $instance->stop;
         }

 9) Calls to AWS that have failed for one reason or another (invalid
    parameters, communications problems, service interruptions) will
    return undef and set the VM::EC2->is_error() method to true. The
    error message and its code can then be recovered by calling
    VM::EC2->error.

      $i = $ec2->describe_instance('i-123456');
      unless ($i) {
          warn 'Got no instance. Message was: ',$ec2->error;
      }

    You may also elect to raise an exception when an error occurs.
    See the new() method for details.
 
=head1 CORE METHODS

This section describes the VM::EC2 constructor, accessor methods, and
methods relevant to error handling.

=cut

use strict;
use LWP::UserAgent;
use HTTP::Request::Common;
use MIME::Base64 qw(encode_base64 decode_base64);
use Digest::SHA qw(hmac_sha256 sha1_hex);
use POSIX 'strftime';
use URI;
use URI::Escape;
use VM::EC2::Dispatch;
use Carp 'croak';

our $VERSION = '0.1';
our $AUTOLOAD;
our @CARP_NOT = qw(VM::EC2::Image    VM::EC2::Volume
                   VM::EC2::Snapshot VM::EC2::Instance);

sub AUTOLOAD {
    my $self = shift;
    my ($pack,$func_name) = $AUTOLOAD=~/(.+)::([^:]+)$/;
    return if $func_name eq 'DESTROY';
    my $proper = VM::EC2->canonicalize($func_name);
    $proper =~ s/^-//;
    if ($self->can($proper)) {
	eval "sub $pack\:\:$func_name {shift->$proper(\@_)}";
	$self->$func_name(@_);
    } else {
	croak "Can't locate object method \"$func_name\" via package \"$pack\"";
    }
}


=head2 $ec2 = VM::EC2->new(-access_key=>$id,-secret_key=>$key,-endpoint=>$url)

Create a new Amazon access object. Required parameters are:

 -access_key   Access ID for an authorized user

 -secret_key   Secret key corresponding to the Access ID

 -endpoint     The URL for making API requests

 -raise_error  If true, throw an exception.

One or more of -access_key, -secret_key and -endpoint can be omitted
if the environment variables EC2_ACCESS_KEY, EC2_SECRET_KEY and
EC2_URL are defined.

By default, when the Amazon API reports an error, such as attempting
to perform an invalid operation on an instance, the corresponding
method will return empty and the error message can be recovered from
$ec2->error(). However, if you pass -raise_error=>1 to new(), the module
will instead raise a fatal error, which you can trap with eval{} and
report with $@:

  eval {
     $ec2->some_dangerous_operation();
     $ec2->another_dangerous_operation();
  };
  print STDERR "something bad happened: $@" if $@;

The error object can be retrieved with $ec2->error() as before.

=cut

sub new {
    my $self = shift;
    my %args = @_;
    my $id           = $args{-access_key} || $ENV{EC2_ACCESS_KEY}
                       or croak "Please provide AccessKey parameter or define environment variable EC2_ACCESS_KEY";
    my $secret       = $args{-secret_key} || $ENV{EC2_SECRET_KEY} 
                       or croak "Please provide SecretKey parameter or define environment variable EC2_SECRET_KEY";
    my $endpoint_url = $args{-endpoint}   || $ENV{EC2_URL} || 'http://ec2.amazonaws.com/';
    $endpoint_url   .= '/' unless $endpoint_url =~ m!/$!;

    my $raise_error  = $args{-raise_error};
    return bless {
	id              => $id,
	secret          => $secret,
	endpoint        => $endpoint_url,
	idempotent_seed => sha1_hex(rand()),
	raise_error     => $raise_error,
    },ref $self || $self;
}

=head2 $access_key = $ec2->access_key(<$new_access_key>)

Get or set the ACCESS KEY

=cut

sub access_key {shift->id(@_)}

sub id       { 
    my $self = shift;
    my $d    = $self->{id};
    $self->{id} = shift if @_;
    $d;
}

=head2 $secret = $ec2->secret(<$new_secret>)

Get or set the SECRET KEY

=cut

sub secret   {
    my $self = shift;
    my $d    = $self->{secret};
    $self->{secret} = shift if @_;
    $d;
}

=head2 $endpoint = $ec2->endpoint(<$new_endpoint>)

Get or set the ENDPOINT URL.

=cut

sub endpoint { 
    my $self = shift;
    my $d    = $self->{endpoint};
    $self->{endpoint} = shift if @_;
    $d;
 }

=head2 $ec2->raise_error($boolean)

Change the handling of error conditions. Pass a true value to cause
Amazon API errors to raise a fatal error. Pass false to make methods
return undef. In either case, you can detect the error condition
by calling is_error() and fetch the error message using error(). This
method will also return the current state of the raise error flag.

=cut

sub raise_error {
    my $self = shift;
    my $d    = $self->{raise_error};
    $self->{raise_error} = shift if @_;
    $d;
}

=head2 $boolean = $ec2->is_error

If a method fails, it will return undef. However, some methods, such
as describe_images(), will also return undef if no resources matches
your search criteria. Call is_error() to distinguish the two
eventualities:

  @images = $ec2->describe_images(-owner=>'29731912785');
  unless (@images) {
      die "Error: ",$ec2->error if $ec2->is_error;
      print "No appropriate images found\n";
  }

=cut

sub is_error {
    defined shift->error();
}

=head2 $err = $ec2->error

If the most recently-executed method failed, $ec2->error() will return
the error code and other descriptive information. This method will
return undef if the most recently executed method was successful.

The returned object is actually an AWS::Error object, which
has two methods named code() and message(). If used in a string
context, its operator overloading returns the composite string
"$message [$code]".

=cut

sub error {
    my $self = shift;
    my $d    = $self->{error};
    $self->{error} = shift if @_;
    $d;
}

=head1 EC2 REGIONS AND AVAILABILITY ZONES

This section describes methods that allow you to fetch information on
EC2 regions and availability zones. These methods return objects of
type L<VM::EC2::Region> and L<VM::EC2::AvailabilityZone>.

=head2 @instances = $ec2->describe_regions(-region_name=>\@list)

=head2 @instances = $ec2->describe_regions(@list)

Describe regions and return a list of VM::EC2::Region objects. Call
with no arguments to return all regions. You may provide a list of
regions in either of the two forms shown above in order to restrict
the list returned. Glob-style wildcards, such as "*east") are allowed.

=cut

sub describe_regions {
    my $self = shift;
    my %args = $self->args('-region_name',@_);
    my @params = $self->list_parm('RegionName',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeRegions',@params);
}

=head2 @instances = $ec2->describe_availability_zones(-zone_name=>\@names,-filter=>\%filters)

=head2 @instances = $ec2->describe_availability_zones(@names)

Describe availability zones and return a list of
VM::EC2::AvailabilityZone objects. Call with no arguments to return
all availability regions. You may provide a list of regions in either
of the two forms shown above in order to restrict the list
returned. Glob-style wildcards, such as "*east") are allowed.

Availability zone filters are described at
http://docs.amazonwebservices.com/AWSEC2/latest/APIReference/ApiReference-query-DescribeAvailabilityZones.html

=cut

sub describe_availability_zones {
    my $self = shift;
    my %args = $self->args('-zone_name',@_);
    my @params = $self->list_parm('ZoneName',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeAvailabilityZones',@params);
}

=head1 EC2 INSTANCES

The methods in this section allow you to retrieve information about
EC2 instances, launch new instances, control the instance lifecycle
(e.g. starting and stopping them), and fetching the console output
from instances.

The primary object manipulated by these methods is
L<VM::EC2::Instance>. Please see the L<VM::EC2::Instance> manual page
for additional methods that allow you to attach and detach volumes,
modify an instance's attributes, and convert instances into images.

=head2 @instances = $ec2->describe_instances(-instance_id=>\@ids,-filter=>\%filters)

=head2 @instances = $ec2->describe_instances(@instance_ids)

Return a series of VM::EC2::Instance objects. Optional parameters are:

 -instance_id     ID of the instance(s) to return information on. 
                  This can be a string scalar, or an arrayref.
 -filter          Tags and other filters to apply.

There are a large number of filters which can be specified. The filter
argument is a hashreference in which the keys are the filter names,
and the values are the match strings. Some filters accept wildcards.

A typical filter example:

  $ec2->describe_instances(
    -filter        => {'block-device-mapping.device-name'=>'/dev/sdh',
                       'architecture'                    => 'i386',
                       'tag:Role'                        => 'Server'
                      });


There are a large number of potential filters, which are listed at
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeInstances.html.

Note that the objects returned from this method are the instances
themselves, and not a reservation set. The reservation ID can be
retrieved from each instance by calling its reservationId() method.

=cut

sub describe_instances {
    my $self = shift;
    my %args = $self->args('-instance_id',@_);
    my @params;
    push @params,$self->list_parm('InstanceId',\%args);
    push @params,$self->filter_parm(\%args);
    my @i = $self->call('DescribeInstances',@params) or return;
    if (!wantarray) { # scalar context
	return       if @i == 0;
	return $i[0] if @i == 1;
    } else {
	return @i
    }
}

=head2 @i = $ec2->run_instances(%param)

This method will provision and launch one or more instances given an
AMI ID. If successful, the method returns a series of
VM::EC2::Instance objects.

=over 4

=item Required parameters:

  -image_id       ID of an AMI to launch
 
=item Optional parameters:

  -min_count         Minimum number of instances to launch [1]
  -max_count         Maximum number of instances to launch [1]
  -key_name          Name of the keypair to use
  -security_group_id Security group ID to use for this instance.
                     Use an arrayref for multiple group IDs
  -security_group    Security group name to use for this instance.
                     Use an arrayref for multiple values.
  -user_data         User data to pass to the instances. Do NOT base64
                     encode this. It will be done for you.
  -instance_type     Type of the instance to use. See below for a
                     list.
  -placement_zone    The availability zone you want to launch the
                     instance into. Call $ec2->regions for a list.
  -placement_group   An existing placement group to launch the
                     instance into. Applicable to cluster instances
                     only.
  -placement_tenancy Specify 'dedicated' to launch the instance on a
                     dedicated server. Only applicable for VPC
                     instances.
  -ramdisk_id        ID of the ramdisk to use for the instances,
                     overriding the ramdisk specified in the image.
  -block_devices     Specify block devices to map onto the instances,
                     overriding the values specified in the image.
                     See below for the syntax of this argument.
  -monitoring        Pass a true value to enable detailed monitoring.
  -subnet_id         ID of the subnet to launch the instance
                     into. Only applicable for VPC instances.
  -termination_protection  Pass true to lock the instance so that it
                     cannot be terminated using the API. Use
                     modify_instance() to unset this if youu wish to
                     terminate the instance later.
  -disable_api_termination -- Same as above.
  -shutdown_behavior Pass "stop" (the default) to stop the instance
                     and save its disk state when "shutdown" is called
                     from within the instance. Stopped instances can
                     be restarted later. Pass "terminate" to
                     instead terminate the instance and discard its
                     state completely.
  -instance_initiated_shutdown_behavior -- Same as above.
  -private_ip_address Assign the instance to a specific IP address
                     from a VPC subnet (VPC only).
  -client_token      Unique identifier that you can provide to ensure
                     idempotency of the request. You can use
                     $ec2->token() to generate a suitable identifier.
                     See http://docs.amazonwebservices.com/AWSEC2/
                         latest/UserGuide/Run_Instance_Idempotency.html

=item Instance types

The following is the list of instance types currently allowed by
Amazon:

   m1.small   c1.medium  m2.xlarge   cc1.4xlarge  cg1.4xlarge  t1.micro
   m1.large   c1.xlarge  m2.2xlarge   
   m1.xlarge             m2.4xlarge

=item Block device syntax

The syntax of -block_devices is identical to what is used by the
ec2-run-instances command-line tool. Borrowing from the manual page of
that tool:

The format is '<device>=<block-device>', where 'block-device' can be one of the
following:
          
    - 'none': indicates that a block device that would be exposed at the
       specified device should be suppressed. For example: '/dev/sdb=none'
          
     - 'ephemeral[0-3]': indicates that the Amazon EC2 ephemeral store
       (instance local storage) should be exposed at the specified device.
       For example: '/dev/sdc=ephemeral0'.
          
     - '[<snapshot-id>][:<size>[:<delete-on-termination>]]': indicates
       that an Amazon EBS volume, created from the specified Amazon EBS
       snapshot, should be exposed at the specified device. The following
       combinations are supported:
          
         - '<snapshot-id>': the ID of an Amazon EBS snapshot, which must
           be owned by or restorable by the caller. May be left out if a
           <size> is specified, creating an empty Amazon EBS volume of
           the specified size.
          
         - '<size>': the size (GiBs) of the Amazon EBS volume to be
           created. If a snapshot was specified, this may not be smaller
           than the size of the snapshot itself.
          
         - '<delete-on-termination>': indicates whether the Amazon EBS
            volume should be deleted on instance termination. If not
            specified, this will default to 'true' and the volume will be
            deleted.
          
         For example: -block_devices => '/dev/sdb=snap-7eb96d16'
                      -block_devices => '/dev/sdc=snap-7eb96d16:80:false'
                      -block_devices => '/dev/sdd=:120'

To provide multiple mappings, use an array reference. In this example,
we launch two 'm1.small' instance in which /dev/sdb is mapped to
ephemeral storage and /dev/sdc is mapped to a new 100 G EBS volume:

 @i=$ec2->run_instances(-image_id  => 'ami-12345',
                        -min_count => 2,
                        -block_devices => ['/dev/sdb=ephemeral0',
                                           '/dev/sdc=:100:true']
    )

=item Return value

On success, this method returns a list of VM::EC2::Instance
objects. If called in a scalar context AND only one instance was
requested, it will return a single instance object (rather than
returning a list of size one which is then converted into numeric "1",
as would be the usual Perl behavior).

Note that this behavior is different from the Amazon API, which
returns a ReservationSet. In this API, ask the instances for the
the reservation, owner, requester, and group information using
reservationId(), ownerId(), requesterId() and groups() methods.

=item Tips

1. If you have a VM::EC2::Image object returned from
   describe_images(), you may run it using run_instances():

 my $image = $ec2->describe_images(-image_id  => 'ami-12345');
 $image->run_instances( -min_count => 10,
                        -block_devices => ['/dev/sdb=ephemeral0',
                                           '/dev/sdc=:100:true']
    )

2. Each instance object has a current_status() method which will
   return the current run state of the instance. You may poll this
   method to wait until the instance is running:

   my ($instance) = $ec2->run_instances(...);
   while ($instance->current_status ne 'running') {
      sleep 5;
   }

3. The utility method wait_for_instances() will wait until all
   passed instances are in 'running' state.

   my @instances = $ec2->run_instances(...);
   $ec2->wait_for_instances(@instances);

=back
 
=cut

sub run_instances {
    my $self = shift;
    my %args = @_;
    $args{-image_id}  or croak "run_instances(): -image_id argument missing";
    $args{-min_count} ||= 1;
    $args{-max_count} ||= $args{-min_count};

    my @p = map {$self->single_parm($_,\%args) }
       qw(ImageId MinCount MaxCount KeyName RamdiskId PrivateIPAddress
          InstanceInitiatedShutdownBehavior ClientToken SubnetId InstanceType);
    push @p,map {$self->list_parm($_,\%args)} qw(SecurityGroup SecurityGroupId);
    push @p,('UserData' =>encode_base64($args{user_data}))            if $args{-user_data};
    push @p,('Placement.AvailabilityZone'=>$args{-availability_zone}) if $args{-placement_zone};
    push @p,('Placement.GroupName'=>$args{-group_name})               if $args{-placement_group};
    push @p,('Placement.Tenancy'=>$args{-tenancy})                    if $args{-placement_tenancy};
    push @p,('Monitoring.Enabled'   =>'true')                         if $args{-monitoring};
    push @p,('DisableApiTermination'=>'true')                         if $args{-termination_protection};
    push @p,('InstanceInitiatedShutdownBehavior'=>$args{-shutdown_behavior}) if $args{-shutdown_behavior};
    push @p,$self->block_device_parm($args{-block_devices})           if $args{-block_devices};
    return $self->call('RunInstances',@p);
}

=head2 @s = $ec2->start_instances(-instance_id=>\@instance_ids)
=head2 @s = $ec2->start_instances(@instance_ids)

Start the instances named by @instance_ids and return one or more
VM::EC2::Instance::State::Change objects.

To wait for the all the instance ids to reach their final state
("running" unless an error occurs), call wait_for_instances().

Example:

    # find all stopped instances
    @instances = $ec2->describe_instances(-filter=>{'instance-state-name'=>'stopped'});

    # start them
    $ec2->start_instances(@instances)

    # pause till they are running (or crashed)
    $ec2->wait_for_instances(@instances)

You can also start an instance by calling the object's start() method:

    $instances[0]->start('wait');  # start instance and wait for it to
				   # be running

The objects returned by calling start_instances() indicate the current
and previous states of the instance. The previous state is typically
"stopped" and the current state is usually "pending." This information
is only current to the time that the start_instances() method was called.
To get the current run state of the instance, call its status()
method:

  die "ouch!" unless $instances[0]->current_status eq 'running';

=cut

sub start_instances {
    my $self = shift;
    my @instance_ids = $self->instance_parm(@_)
	or croak "usage: start_instances(\@instance_ids)";
    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    return $self->call('StartInstances',@params) or return;
}

=head2 @s = $ec2->stop_instances(-instance_id=>\@instance_ids,-force=>1)

=head2 @s = $ec2->stop_instances(@instance_ids)

Stop the instances named by @instance_ids and return one or more
VM::EC2::Instance::State::Change objects. In the named parameter
version of this method, you may optionally provide a -force argument,
which if true, forces the instance to halt without giving it a chance
to run its shutdown procedure (the equivalent of pulling a physical
machine's plug).

To wait for instances to reach their final state, call
wait_for_instances().

Example:

    # find all running instances
    @instances = $ec2->describe_instances(-filter=>{'instance-state-name'=>'running'});

    # stop them immediately and wait for confirmation
    $ec2->stop_instances(-instance_id=>\@instances,-force=>1);
    $ec2->wait_for_instances(@instances);

You can also stop an instance by calling the object's start() method:

    $instances[0]->stop('wait');  # stop first instance and wait for it to
			          # stop completely

=cut

sub stop_instances {
    my $self = shift;
    my (@instance_ids,$force);

    if ($_[0] =~ /^-/) {
	my %argv   = @_;
	@instance_ids = ref $argv{-instance_id} ?
	               @{$argv{-instance_id}} : $argv{-instance_id};
	$force     = $argv{-force};
    } else {
	@instance_ids = @_;
    }
    @instance_ids or croak "usage: stop_instances(\@instance_ids)";    

    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    push @params,Force=>1 if $force;
    return $self->call('StopInstances',@params) or return;
}

=head2 @s = $ec2->terminate_instances(-instance_id=>\@instance_ids)

=head2 @s = $ec2->terminate_instances(@instance_ids)

Terminate the instances named by @instance_ids and return one or more
VM::EC2::Instance::State::Change objects. This method will fail
for any instances whose termination protection field is set.

To wait for the all the instances to reach their final state, call
wait_for_instances().

Example:

    # find all instances tagged as "Version 0.5"
    @instances = $ec2->describe_instances(-filter=>{'tag:Version'=>'0.5'});

    # terminate them
    $ec2->terminate_instances(@instances);

You can also terminate an instance by calling its terminate() method:

    $instances[0]->terminate;

=cut

sub terminate_instances {
    my $self = shift;
    my @instance_ids = $self->instance_parm(@_)
	or croak "usage: start_instances(\@instance_ids)";
    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    return $self->call('TerminateInstances',@params) or return;
}

=head2 @s = $ec2->reboot_instances(-instance_id=>\@instance_ids)
=head2 @s = $ec2->reboot_instances(@instance_ids)

Reboot the instances named by @instance_ids and return one or more
VM::EC2::Instance::State::Change objects.

To wait for the all the instances to reach their final state, call
wait_for_instances().

You can also reboot an instance by calling its terminate() method:

    $instances[0]->reboot;

=cut

sub reboot_instances {
    my $self = shift;
    my @instance_ids = $self->instance_parm(@_)
	or croak "Usage: reboot_instances(\@instance_ids)";
    my $c = 1;
    my @params = map {'InstanceId.'.$c++,$_} @instance_ids;
    return $self->call('RebootInstances',@params) or return;
}

=head2 $t = $ec2->token

Return a client token for use with start_instances().

=cut

sub token {
    my $self = shift;
    my $seed = $self->{idempotent_seed};
    $self->{idempotent_seed} = sha1_hex($seed);
    $seed =~ s/(.{6})/$1-/g;
    return $seed;
}

=head2 $ec2->wait_for_instances(-instance_id=>\@instances);

=head2 $ec2->wait_for_instances(@instances)

Wait for all members of the provided list of instances to reach some
terminal state ("running", "stopped" or "terminated"), and then return
a true value.

=cut

sub wait_for_instances {
    my $self = shift;
    my @instances = @_;
    my %terminal_state = (running    => 1,
			  stopped    => 1,
			  terminated => 1);
    my @pending = grep {!$terminal_state{$_->current_status}} @instances;

    while (@pending) {
	sleep 3;
	@pending = grep {!$terminal_state{$_->current_status}} @pending;
    }
}

=head2 $output = $ec2->get_console_output(-instance_id=>'i-12345')

=head2 $output = $ec2->get_console_output('i-12345');

Return the console output of the indicated instance. The output is
actually a VM::EC2::ConsoleOutput object, but it is
overloaded so that when treated as a string it will appear as a
large text string containing the  console output. When treated like an
object it provides instanceId() and timestamp() methods.

=cut

sub get_console_output {
    my $self = shift;
    my %args = $self->args(-instance_id=>@_);
    $args{-instance_id} or croak "Usage: get_console_output(-instance_id=>\$id)";
    my @params = $self->single_parm('InstanceId',\%args);
    return $self->call('GetConsoleOutput',@params);
}

=head2 @monitoring_state = $ec2->monitor_instances(@list_of_instanceIds)

=head2 @monitoring_state = $ec2->monitor_instances(-instance_id=>\@instanceIds)

This method enables monitoring for the listed instances and returns a
list of VM::EC2::Instance::MonitoringState objects. You can
later use these objects to activate and inactivate monitoring.

=cut

sub monitor_instances {
    my $self = shift;
    my %args = $self->args('-instance_id',@_);
    my @params = $self->list_parm('InstanceId',\%args);
    return $self->call('MonitorInstances',@params);
}

=head2 @monitoring_state = $ec2->unmonitor_instances(@list_of_instanceIds)

=head2 @monitoring_state = $ec2->unmonitor_instances(-instance_id=>\@instanceIds)

This method disables monitoring for the listed instances and returns a
list of VM::EC2::Instance::MonitoringState objects. You can
later use these objects to activate and inactivate monitoring.

=cut

sub unmonitor_instances {
    my $self = shift;
    my %args = $self->args('-instance_id',@_);
    my @params = $self->list_parm('InstanceId',\%args);
    return $self->call('UnmonitorInstances',@params);
}

=head2 $meta = $ec2->instance_metadata

B<For use on running EC2 instances only:> This method returns a
VM::EC2::Instance::Metadata object that will return information about
the currently running instance using the HTTP:// metadata fields
described at
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?instancedata-data-categories.html. This
is usually fastest way to get runtime information on the current
instance.

=cut

sub instance_metadata {
    VM::EC2::Dispatch::load_module('VM::EC2::Instance::Metadata');
    return VM::EC2::Instance::Metadata->new();
}

=head2 @data = $ec2->describe_instance_attribute($instance_id,$attribute)

This method returns instance attributes. Only one attribute can be
retrieved at a time. The following is the list of attributes that can be
retrieved:

 instanceType
 kernel
 ramdisk
 userData
 disableApiTermination
 instanceInitiatedShutdownBehavior
 rootDeviceName
 blockDeviceMapping
 sourceDestCheck
 groupSet

All of these values can be retrieved more conveniently from the
L<VM::EC2::Instance> object returned from describe_instances(), so
there is no attempt to parse the results of this call into Perl
objects. Therefore, some of the attributes, such as
'blockDeviceMapping' will be returned as raw hashrefs.

=cut

sub describe_instance_attribute {
    my $self = shift;
    @_ == 2 or croak "Usage: describe_instance_attribute(\$instance_id,\$attribute_name)";
    my ($instance_id,$attribute) = @_;
    my @param  = (InstanceId=>$instance_id,Attribute=>$attribute);
    my $result = $self->call('DescribeInstanceAttribute',@param);
    return $result->attribute($attribute);
}

=head2 $boolean = $ec2->modify_instance_attribute($instance_id,%param)

This method changes instance attributes. It can only be applied to stopped instances.
The following is the list of attributes that can be set:

 -instance_type           -- type of instance, e.g. "m1.small"
 -kernel                  -- kernel id
 -ramdisk                 -- ramdisk id
 -user_data               -- user data
 -termination_protection  -- true to prevent termination from the console
 -disable_api_termination -- same as the above
 -shutdown_behavior       -- "stop" or "terminate"
 -instance_initiated_shutdown_behavior -- same as above
 -root_device_name        -- root device name
 -source_dest_check       -- enable NAT (VPC only)
 -group_id                -- VPC security group

For example:

  $ec2->modify_instance_attribute('i-12345',-kernel=>'aki-f70657b2',-ramdisk=>'ari-21113')

The result code is true if the attribute was successfully modified,
false otherwise. In the latter case, $ec2->error() will provide the
error message.

=cut

sub modify_instance_attribute {
    my $self = shift;
    my $instance_id = shift or croak "Usage: modify_instance_attribute(\$instanceId,%param)";
    my %args   = @_;

    my @param  = (InstanceId=>$instance_id);
    push @param,$self->value_parm($_,\%args) foreach 
	qw(InstanceType Kernel Ramdisk UserData DisableApiTermination
           InstanceInitiatedShutdownBehavior SourceDestCheck);
    push @param,$self->list_parm('GroupId',\%args);
    push @param,('DisableApiTermination.Value'=>'true') if $args{-termination_protection};
    push @param,('InstanceInitiatedShutdownBehavior.Value'=>$args{-shutdown_behavior}) if $args{-shutdown_behavior};

    return $self->call('ModifyInstanceAttribute',@param);
}

=head2 $boolean = $ec2->reset_instance_attribute($instance_id,$attribute)

This method resets an attribute of the given instance to its default
value. Valid attributes are "kernel", "ramdisk" and
"sourceDestCheck". The result code is true if the reset was
successful.

=cut

sub reset_instance_attribute {
    my $self = shift;
    @_      == 2 or croak "Usage: reset_instance_attribute(\$instanceId,\$attribute_name)";
    my ($instance_id,$attribute) = @_;
    my %valid = map {$_=>1} qw(kernel ramdisk sourceDestCheck);
    $valid{$attribute} or croak "attribute to reset must be one of 'kernel', 'ramdisk', or 'sourceDestCheck'";
    return $self->call('ResetInstanceAttribute',InstanceId=>$instance_id,Attribute=>$attribute);
}

=head1 EC2 AMAZON MACHINE IMAGES

The methods in this section allow you to query and manipulate Amazon
machine images (AMIs). See L<VM::EC2::Image>.

=head2 @i = $ec2->describe_images(-image_id=>\@id,-executable_by=>$id,
                                  -owner=>$id, -filter=>\%filters)

=head2 @i = $ec2->describe_images(@image_ids)

Return a series of VM::EC2::Image objects, each describing an
AMI. Optional parameters:

 -image_id        The id of the image, either a string scalar or an
                  arrayref.
 -executable_by   Filter by images executable by the indicated user account
 -owner           Filter by owner account
 -filter          Tags and other filters to apply

The full list of image filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeImages.html

=cut

sub describe_images {
    my $self = shift;
    my %args = $self->args(-image_id=>@_);
    my @params;
    push @params,$self->list_parm($_,\%args) foreach qw(ExecutableBy ImageId Owner);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeImages',@params) or return;
}


=head1 EC2 VOLUMES AND SNAPSHOTS

The methods in this section allow you to query and manipulate EC2 EBS
volumes and snapshots. See L<VM::EC2::Volume> and L<VM::EC2::Snapshot>
for additional functionality provided through the object interface.

=head2 @v = $ec2->describe_volumes(-volume_id=>\@ids,-filter=>\%filters)

=head2 @v = $ec2->describe_volumes(@volume_ids)

Return a series of VM::EC2::Volume objects. Optional parameters:

 -volume_id    The id of the volume to fetch, either a string
               scalar or an arrayref.
 -filter       One or more filters to apply to the search

The full list of volume filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeVolumes.html

=cut

sub describe_volumes {
    my $self = shift;
    my %args = $self->args(-volume_id=>@_);
    my @params;
    push @params,$self->list_parm('VolumeId',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeVolumes',@params) or return;
}

=head2 $v = $ec2->create_volume(-availability_zone=>$zone,-snapshot_id=>$snapshotId,-size=>$size)

Create a volume in the specified availability zone and return
information about it.

Arguments:

 -availability_zone    -- An availability zone from
                          describe_availability_zones (required)
 -snapshot_id          -- ID of a snapshot to use to build volume from.
 -size                 -- Size of the volume, in GB (between 1 and 1024).

One or both of -snapshot_id or -size are required. For convenience,
you may abbreviate -availability_zone as -zone, and -snapshot_id as
-snapshot.

The returned object is a VM::EC2::Volume object.

=cut

sub create_volume {
    my $self = shift;
    my %args = @_;
    my $zone = $args{-availability_zone} || $args{-zone} or croak "-availability_zone argument is required";
    my $snap = $args{-snapshot_id}       || $args{-snapshot};
    my $size = $args{-size};
    $snap || $size or croak "One or both of -snapshot_id or -size are required";
    my @params = (AvailabilityZone => $zone);
    push @params,(SnapshotId   => $snap) if $snap;
    push @params,(Size => $size)         if $size;
    return $self->call('CreateVolume',@params) or return;
}

=head2 $result = $ec2->delete_volume($volume_id);

Deletes the specified volume. Returns a boolean indicating success of
the delete operation. Note that a volume will remain in the "deleting"
state for some time after this call completes.

=cut

sub delete_volume {
    my $self = shift;
    my %args  = $self->args(-volume_id => @_);
    my @param = $self->single_parm(VolumeId=>\%args);
    return $self->call('DeleteVolume',@param) or return;
}

=head2 $attachment = $ec2->attach_volume($volume_id,$instance_id,$device);

=head2 $attachment = $ec2->attach_volume(-volume_id=>$volume_id,-instance_id=>$instance_id,-device=>$device);

Attaches the specified volume to the instance using the indicated
device. All arguments are required:

 -volume_id      -- ID of the volume to attach. The volume must be in
                    "available" state.
 -instance_id    -- ID of the instance to attach to. Both instance and
                    attachment must be in the same availability zone.
 -device         -- How the device is exposed to the instance, e.g.
                    '/dev/sdg'.

The result is a VM::EC2::BlockDevice::Attachment object which
you can monitor by calling current_status():

    my $a = $ec2->attach_volume('vol-12345','i-12345','/dev/sdg');
    while ($a->current_status ne 'attached') {
       sleep 2;
    }
    print "volume is ready to go\n";

=cut

sub attach_volume {
    my $self = shift;
    my %args;
    if ($_[0] !~ /^-/ && @_ == 3) {
	@args{qw(-volume_id -instance_id -device)} = @_;
    } else {
	%args = @_;
    }
    $args{-volume_id} && $args{-instance_id} && $args{-device}
      or croak "-volume_id, -instance_id and -device arguments must all be specified";
    my @param = $self->single_parm(VolumeId=>\%args);
    push @param,$self->single_parm(InstanceId=>\%args);
    push @param,$self->single_parm(Device=>\%args);
    return $self->call('AttachVolume',@param) or return;
}

=head2 $attachment = $ec2->detach_volume($volume_id)

=head2 $attachment = $ec2->detach_volume(-volume_id=>$volume_id,-instance_id=>$instance_id,
                                         -device=>$device,      -force=>$force);

Detaches the specified volume from an instance.

 -volume_id      -- ID of the volume to detach. (required)
 -instance_id    -- ID of the instance to detach from. (optional)
 -device         -- How the device is exposed to the instance. (optional)
 -force          -- Force detachment, even if previous attempts were
                    unsuccessful. (optional)


The result is a VM::EC2::BlockDevice::Attachment object which
you can monitor by calling current_status():

    my $a = $ec2->detach_volume('vol-12345');
    while ($a->current_status ne 'detached') {
       sleep 2;
    }
    print "volume is ready to go\n";

=cut

sub detach_volume {
    my $self = shift;
    my %args = $self->args(-volume_id => @_);
    my @param = $self->single_parm(VolumeId=>\%args);
    push @param,$self->single_parm(InstanceId=>\%args);
    push @param,$self->single_parm(Device=>\%args);
    push @param,$self->single_parm(Force=>\%args);
    return $self->call('DetachVolume',@param) or return;
}

=head2 @snaps = $ec2->describe_snapshots(-snapshot_id=>\@ids,%other_param)

=head2 @snaps = $ec2->describe_snapshots(@snapshot_ids)

Returns a series of VM::EC2::Snapshot objects. All parameters
are optional:

 -snapshot_id     ID of the snapshot
 -owner           Filter by owner ID
 -restorable_by   Filter by IDs of a user who is allowed to restore
                   the snapshot
 -filter          Tags and other filters

The full list of applicable filters can be found at
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeSnapshots.html

=cut

sub describe_snapshots {
    my $self = shift;
    my %args = $self->args('-snapshot_id',@_);

    my @params;
    push @params,$self->list_parm('SnapshotId',\%args);
    push @params,$self->list_parm('Owner',\%args);
    push @params,$self->list_parm('RestorableBy',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeSnapshots',@params) or return;
}

=head1 SECURITY GROUPS AND KEY PAIRS

The methods in this section allow you to query and manipulate security
groups (firewall rules) and SSH key pairs. See
L<VM::EC2::SecurityGroup> and L<VM::EC2::KeyPair> for functionality
that is available through these objects.

=head2 @sg = $ec2->describe_security_groups(-group_id  => \@ids,
                                            -group_name=> \@names,
                                            -filter    => \%filters);

=head2 @sg = $ec2->describe_security_groups(@group_ids)

Searches for security groups (firewall rules) matching the provided
filters and return a series of VM::EC2::SecurityGroup objects.

Optional parameters:

 -group_name      A single group name or an arrayref containing a list
                   of names
 -group_id        A single group id (i.e. 'sg-12345') or an arrayref
                   containing a list of ids
 -filter          Filter on tags and other attributes.

The full list of security group filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeSecurityGroups.html

=cut

sub describe_security_groups {
    my $self = shift;
    my %args = $self->args(-group_id=>@_);
    my @params = map { $self->list_parm($_,\%args) } qw(GroupName GroupId);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeSecurityGroups',@params);
}

=head2 @keys = $ec2->describe_key_pairs(-key_name => \@names,
                                   -filter    => \%filters);
=head2 @keys = $ec2->describe_key_pairs(@names);

Searches for ssh key pairs matching the provided filters and return
a series of VM::EC2::KeyPair objects.

Optional parameters:

 -key_name      A single key name or an arrayref containing a list
                   of names
 -filter          Filter on tags and other attributes.

The full list of key filters can be found at:
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeKeyPairs.html

=cut

sub describe_key_pairs {
    my $self = shift;
    my %args = $self->args(-key_name=>@_);
    my @params = $self->list_parm('KeyName',\%args);
    push @params,$self->filter_parm(\%args);
    return $self->call('DescribeKeyPairs',@params);
}

=head2 $key = $ec2->create_key_pair($name)

Create a new key pair with the specified name (required). If the key
pair already exists, returns undef. The contents of the new keypair,
including the PEM-encoded private key, is contained in the returned
VM::EC2::KeyPair object:

  my $key = $ec2->create_key_pair('My Keypair');
  if ($key) {
    print $key->fingerprint,"\n";
    print $key->privateKey,"\n";
  }

=cut

sub create_key_pair {
    my $self = shift; 
    my $name = shift or croak "Usage: create_key_pair(\$name)"; 
    $name =~ /^[\w _-]+$/
	or croak    "Invalid keypair name: must contain only alphanumerics, spaces, dashes and underscores";
    my @params = (KeyName=>$name);
    $self->call('CreateKeyPair',@params);
}

=head2 $key = $ec2->import_key_pair(-key_name=>$name,
                                    -public_key_material=>$public_key)

=head2 $key = $ec2->import_key_pair($name,$public_key)

Imports a preexisting public key into AWS under the specified name.
If successful, returns a VM::EC2::KeyPair. The public key must be an
RSA key of length 1024, 2048 or 4096. The method can be called with
two unnamed arguments consisting of the key name and the public key
material, or in a named argument form with the following argument
names:

  -key_name     -- desired name for the imported key pair (required)
  -name         -- shorter version of -key_name

  -public_key_material -- public key data (required)
  -public_key   -- shorter version of the above

This example uses Net::SSH::Perl::Key to generate a new keypair, and
then uploads the public key to Amazon.

  use Net::SSH::Perl::Key;

  my $newkey = Net::SSH::Perl::Key->keygen('RSA',1024);
  $newkey->write_private('.ssh/MyKeypair.rsa');  # save private parts

  my $key = $ec2->import_key_pair('My Keypair' => $newkey->dump_public)
      or die $ec2->error;
  print "My Keypair added with fingerprint ",$key->fingerprint,"\n";

Several different formats are accepted for the key, including SSH
"authorized_keys" format (generated by L<ssh-keygen> and
Net::SSH::Perl::Key), the SSH public keys format, and DER format. You
do not need to base64-encode the key or perform any other
pre-processing.

Note that the algorithm used by Amazon to calculate its key
fingerprints differs from the one used by the ssh library, so don't
try to compare the key fingerprints returned by Amazon to the ones
produced by ssh-keygen or Net::SSH::Perl::Key.

=cut

sub import_key_pair {
    my $self = shift; 
    my %args;
    if (@_ == 2 && $_[0] !~ /^-/) {
	%args = (-key_name            => shift,
		 -public_key_material => shift);
    } else {
	%args = @_;
    }
    my $name = $args{-key_name}           || $args{-name}        or croak "-key_name argument required";
    my $pkm  = $args{-public_key_material}|| $args{-public_key}  or croak "-public_key_material argument required";
    my @params = (KeyName => $name,PublicKeyMaterial=>encode_base64($pkm));
    $self->call('ImportKeyPair',@params);
}

=head2 $result = $ec2->delete_key_pair($name)

Deletes the key pair with the specified name (required). Returns true
if successful.

=cut

sub delete_key_pair {
    my $self = shift; my $name = shift or croak "Usage: create_key_pair(\$name)"; 
    $name =~ /^[\w _-]+$/
	or croak    "Invalid keypair name: must contain only alphanumerics, spaces, dashes and underscores";
    my @params = (KeyName=>$name);
    $self->call('DeleteKeyPair',@params);
}

=head1 TAGS

These methods allow you to create, delete and fetch resource tags. You
may find that you rarely need to use these methods directly because
every object produced by VM::EC2 supports a simple tag interface:

  $object = $ec2->describe_volumes(-volume_id=>'vol-12345'); # e.g.
  $tags = $object->tags();
  $name = $tags->{Name};
  $object->add_tags(Role => 'Web Server', Status=>'development);
  $object->delete_tags(Name=>undef);

See L<VM::EC2::Generic> for a full description of the uniform object
tagging interface.

These methods are most useful when creating and deleting tags for
multiple resources simultaneously.

=head2 @t = $ec2->describe_tags(-filter=>\%filters);

Return a series of VM::EC2::Tag objects, each describing an
AMI. A single optional -filter argument is allowed.

Available filters are: key, resource-id, resource-type and value. See
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeTags.html

=cut

sub describe_tags {
    my $self = shift;
    my %args = @_;
    my @params = $self->filter_parm(\%args);
    return $self->call('DescribeTags',@params);    
}

=head2 $bool = $ec2->create_tags(-resource_id=>\@ids,-tag=>{key1=>value1...})

Tags the resource indicated by -resource_id with the tag(s) in in the
hashref indicated by -tag. You may specify a single resource by
passing a scalar resourceId to -resource_id, or multiple resources
using an anonymous array. Returns a true value if tagging was
successful.

The method name "add_tags()" is an alias for create_tags().

You may find it more convenient to tag an object retrieved with any of
the describe() methods using the built-in add_tags() method:

 @snap = $ec2->describe_snapshots(-filter=>{status=>'completed'});
 foreach (@snap) {$_->add_tags(ReadyToUse => 'true')}

but if there are many snapshots to tag simultaneously, this will be faster:

 @snap = $ec2->describe_snapshots(-filter=>{status=>'completed'});
 $ec2->add_tags(-resource_id=>\@snap,-tag=>{ReadyToUse=>'true'});

Note that you can tag volumes, snapshots and images owned by other
people. Only you will be able to see these tags.

=cut

sub create_tags {
    my $self = shift;
    my %args = @_;
    $args{-resource_id} or croak "create_tags() -resource_id argument required";
    $args{-tag}         or croak "create_tags() -tag argument required";
    my @params = $self->list_parm('ResourceId',\%args);
    push @params,$self->tagcreate_parm(\%args);
    return $self->call('CreateTags',@params);    
}

sub add_tags { shift->create_tags(@_) }

=head2 $bool = $ec2->delete_tags(-resource_id=>$id1,-tag=>{key1=>value1...})

Delete the indicated tags from the indicated resource. Pass an
arrayref to operate on several resources at once. The tag syntax is a
bit tricky. Use a value of undef to delete the tag unconditionally:

 -tag => { Role => undef }    # deletes any Role tag

Any scalar value will cause the tag to be deleted only if its value
exactly matches the specified value:

 -tag => { Role => 'Server' }  # only delete the Role tag
                               # if it currently has the value "Server"

An empty string value ('') will only delete the tag if its value is an
empty string, which is probably not what you want.

Pass an array reference of tag names to delete each of the tag names
unconditionally (same as passing a value of undef):

 $ec2->delete_tags(['Name','Role','Description']);

You may find it more convenient to delete tags from objects using
their delete_tags() method:

 @snap = $ec2->describe_snapshots(-filter=>{status=>'completed'});
 foreach (@snap) {$_->delete_tags(Role => undef)}

=cut

sub delete_tags {
    my $self = shift;
    my %args = @_;
    $args{-resource_id} or croak "create_tags() -resource_id argument required";
    $args{-tag}         or croak "create_tags() -tag argument required";
    my @params = $self->list_parm('ResourceId',\%args);
    push @params,$self->tagdelete_parm(\%args);
    return $self->call('DeleteTags',@params);    
}

=head1 ELASTIC IP ADDRESSES

The methods in this section allow you to allocate elastic IP
addresses, attach them to instances, and delete them. See
L<VM::EC2::ElasticAddress>.

=head2 @addr = $ec2->describe_addresses(-public_ip=>\@addr,-allocation_id=>\@id,-filter->\%filters)

=head2 @addr = $ec2->describe_addresses(@public_ips)

Queries AWS for a list of elastic IP addresses already allocated to
you. All parameters are optional:

 -public_ip     -- An IP address (in dotted format) or an arrayref of
                   addresses to return information about.
 -allocation_id -- An allocation ID or arrayref of such IDs. Only 
                   applicable to VPC addresses.
 -filter        -- A hashref of tag=>value pairs to filter the response
                   on.

The list of applicable filters can be found at
http://docs.amazonwebservices.com/AWSEC2/2011-05-15/APIReference/ApiReference-query-DescribeAddresses.html.

This method returns a list of L<VM::EC2::ElasticAddress>.

=cut

sub describe_addresses {
    my $self = shift;
    my %args = $self->args(-public_ip=>@_);
    my @param;
    push @param,$self->list_parm('PublicIp',\%args);
    push @param,$self->list_parm('AllocationId',\%args);
    push @param,$self->filter_parm(\%args);
    return $self->call('DescribeAddresses',@param);
}

=head2 $address_info = $ec2->allocate_address([-vpc=>1])

Request an elastic IP address. Pass -vpc=>1 to allocate a VPC elastic
address. The return object is a VM::EC2::ElasticAddress.

=cut

sub allocate_address {
    my $self = shift;
    my %args = @_;
    my @param = $args{-vpc} ? (Domain=>'vpc') : ();
    return $self->call('AllocateAddress',@param);
}

=head2 $boolean = $ec2->release_address($addr)

Release an elastic IP address. For non-VPC addresses, you may provide
either an IP address string, or a VM::EC2::ElasticAddress. For VPC
addresses, you must obtain a VM::EC2::ElasticAddress first 
(e.g. with describe_addresses) and then pass that to the method.

=cut

sub release_address {
    my $self = shift;
    my $addr = shift or croak "Usage: release_address(\$addr)";
    my @param = (PublicIp=>$addr);
    if (my $allocationId = eval {$addr->allocationId}) {
	push @param,(AllocatonId=>$allocationId);
    }
    return $self->call('ReleaseAddress',@param);
}

=head2 $result = $ec2->associate_address($elastic_addr => $instance_id)

Associate an elastic address with an instance id. Both arguments are
mandatory. If you are associating a VPC elastic IP address with the
instance, the result code will indicate the associationId. Otherwise
it will be a simple perl truth value ("1") if successful, undef if
false.

If this is an ordinary EC2 Elastic IP address, the first argument may
either be an ordinary string (xx.xx.xx.xx format) or a
VM::EC2::ElasticAddress object. However, if it is a VPC elastic
IP address, then the argument must be a VM::EC2::ElasticAddress
as returned by describe_addresses(). The reason for this is that the
allocationId must be retrieved from the object in order to use in the
call.

=cut

sub associate_address {
    my $self = shift;
    @_ == 2 or croak "Usage: associate_address(\$elastic_addr => \$instance_id)";
    my ($addr,$instance) = @_;

    my @param = (InstanceId=>$instance);
    push @param,eval {$addr->domain eq 'vpc'} ? (AllocationId => $addr->allocationId)
	                                      : (PublicIp     => $addr);
    return $self->call('AssociateAddress',@param);
}

=head2 $bool = $ec2->disassociate_address($elastic_addr)

Disassociate an elastic address from whatever instance it is currently
associated with, if any. The result will be true if disassociation was
successful.

If this is an ordinary EC2 Elastic IP address, the argument may
either be an ordinary string (xx.xx.xx.xx format) or a
VM::EC2::ElasticAddress object. However, if it is a VPC elastic
IP address, then the argument must be a VM::EC2::ElasticAddress
as returned by describe_addresses(). The reason for this is that the
allocationId must be retrieved from the object in order to use in the
call.


=cut

sub disassociate_address {
    my $self = shift;
    @_ == 1 or croak "Usage: associate_address(\$elastic_addr)";
    my $addr = shift;

    my @param = eval {$addr->domain eq 'vpc'} ? (AssociationId => $addr->associationId)
	                                      : (PublicIp      => $addr);
    return $self->call('DisassociateAddress',@param);
}

# ------------------------------------------------------------------------------------------

=head1 INTERNAL METHODS

These methods are used internally and are listed here without
documentation (yet).

=head2 $underscore_name = $ec2->canonicalize($mixedCaseName)

=cut

sub canonicalize {
    my $self = shift;
    my $name = shift;
    while ($name =~ /\w[A-Z]/) {
	$name    =~ s/([a-zA-Z])([A-Z])/\L$1_$2/g;
    }
    return '-'.lc $name;
}

sub uncanonicalize {
    my $self = shift;
    my $name = shift;
    $name    =~ s/_([a-z])/\U$1/g;
    return $name;
}

=head2 $instance_id = $ec2->instance_parm(@args)

=cut

sub instance_parm {
    my $self = shift;
    my %args;
    if ($_[0] =~ /^-/) {
	%args = @_; 
    } else {
	%args = (-instance_id => shift);
    }
    my $id = $args{-instance_id};
    return ref $id && ref $id eq 'ARRAY' ? @$id : $id;
}

=head2 @parameters = $ec2->value_parm(ParameterName => \%args)

=cut

sub value_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);
    return unless exists $args->{$name};
    return ("$argname.Value"=>$args->{$name});
}

=head2 @parameters = $ec2->single_parm(ParameterName => \%args)

=cut

sub single_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);
    return unless exists $args->{$name};
    my $v = ref $args->{$name}  && ref $args->{$name} eq 'ARRAY' ? $args->{$name}[0] : $args->{$name};
    return ($argname=>$v);
}

=head2 @parameters = $ec2->list_parm(ParameterName => \%args)

=cut

sub list_parm {
    my $self = shift;
    my ($argname,$args) = @_;
    my $name = $self->canonicalize($argname);

    my @params;
    if (my $a = $args->{$name}) {
	my $c = 1;
	for (ref $a && ref $a eq 'ARRAY' ? @$a : $a) {
	    push @params,("$argname.".$c++ => $_);
	}
    }

    return @params;
}

=head2 @parameters = $ec2->filter_parm(\%args)

=cut

sub filter_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Filter','Name','Value',$args);
}

=head2 @parameters = $ec2->tagcreate_parm(\%args)

=cut

sub tagcreate_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Tag','Key','Value',$args);
}

=head2 @parameters = $ec2->tagdelete_parm(\%args)

=cut

sub tagdelete_parm {
    my $self = shift;
    my $args = shift;
    return $self->key_value_parameters('Tag','Key','Value',$args,1);
}

=head2 @parameters = $ec2->key_value_parm($param_name,$keyname,$valuename,\%args,$skip_undef_values)

=cut

sub key_value_parameters {
    my $self = shift;
    # e.g. 'Filter', 'Name','Value',{-filter=>{a=>b}}
    my ($parameter_name,$keyname,$valuename,$args,$skip_undef_values) = @_;  
    my $arg_name     = $self->canonicalize($parameter_name);
    
    my @params;
    if (my $a = $args->{$arg_name}) {
	my $c = 1;
	if (ref $a && ref $a eq 'HASH') {
	    while (my ($name,$value) = each %$a) {
		push @params,("$parameter_name.$c.$keyname"   => $name);
		push @params,("$parameter_name.$c.$valuename" => $value)
		    unless !defined $value && $skip_undef_values;
		$c++;
	    }
	} else {
	    for (ref $a ? @$a : $a) {
		my ($name,$value) = /([^=]+)\s*=\s*(.+)/;
		push @params,("$parameter_name.$c.$keyname"   => $name);
		push @params,("$parameter_name.$c.$valuename" => $value)
		    unless !defined $value && $skip_undef_values;
		$c++;
	    }
	}
    }

    return @params;
}

=head2 @parameters = $ec2->block_device_parm($block_device_mapping_string)

=cut

sub block_device_parm {
    my $self    = shift;
    my $devlist = shift;

    my @dev     = ref $devlist ? @$devlist : $devlist;

    my @p;
    my $c = 1;
    for my $d (@dev) {
	$d =~ /^([^=]+)=([^=]+)$/ or croak "block device mapping must be in format /dev/sdXX=device-name";

	my ($devicename,$blockdevice) = ($1,$2);
	push @p,("BlockDeviceMapping.$c.DeviceName"=>$devicename);

	if ($blockdevice eq 'none') {
	    push @p,("BlockDeviceMapping.$c.NoDevice" => '');
	} elsif ($blockdevice =~ /^ephemeral\d$/) {
	    push @p,("BlockDeviceMapping.$c.VirtualName"=>$blockdevice);
	} else {
	    my ($snapshot,$size,$delete_on_term) = split ':',$blockdevice;
	    push @p,("BlockDeviceMapping.$c.Ebs.SnapshotId"=>$snapshot)                if $snapshot;
	    push @p,("BlockDeviceMapping.$c.Ebs.VolumeSize" =>$size)                   if $size;
	    push @p,("BlockDeviceMapping.$c.Ebs.DeleteOnTermination"=>$delete_on_term) 
		if $delete_on_term  && $delete_on_term=~/^(true|false|1|0)$/
	}
	$c++;
    }
    return @p;
}

=head2 $version = $ec2->version()

API version.

=cut

sub version  { '2011-05-15'      }

=head2 $ts = $ec2->timestamp

=cut

sub timestamp {
    return strftime("%Y-%m-%dT%H:%M:%SZ",gmtime);
}


=head2 $ua = $ec2->ua

LWP::UserAgent object.

=cut

sub ua {
    my $self = shift;
    return $self->{ua} ||= LWP::UserAgent->new;
}

=head2 @obj = $ec2->call($action,@param);

Make a call to Amazon using $action and the passed parameters, and
return a list of objects.

=cut

sub call {
    my $self    = shift;
    my $response  = $self->make_request(@_);

    unless ($response->is_success) {
	if ($response->code == 400) {
	    my $error = VM::EC2::Dispatch->create_error_object($response->decoded_content,$self);
	    $self->error($error);
	    croak "$error" if $self->raise_error;
	    return;
	} else {
	    print STDERR $response->request->as_string=~/Action=(\w+)/,': ',$response->status_line,"\n";
	    return;
	}
    }
    $self->error(undef);
    my @obj = VM::EC2::Dispatch->response2objects($response,$self);

    # slight trick here so that we return one object in response to
    # describe_images(-image_id=>'foo'), rather than the number "1"
    if (!wantarray) { # scalar context
	return $obj[0] if @obj == 1;
	return         if @obj == 0;
    } else {
	return @obj;
    }
}

=head2 $request = $ec2->make_request($action,@param);

Set up the signed HTTP::Request object.

=cut

sub make_request {
    my $self    = shift;
    my ($action,@args) = @_;
    my $request = $self->_sign(Action=>$action,@args);
    return $self->ua->request($request);
}

=head2 $request = $ec2->_sign(@args)

Create and sign an HTTP::Request.

=cut

# adapted from Jeff Kim's Net::Amazon::EC2 module
sub _sign {
    my $self    = shift;
    my @args    = @_;

    my $action = 'POST';
    my $host   = lc URI->new($self->endpoint)->host;
    my $path   = '/';

    my %sign_hash                = @args;
    $sign_hash{AWSAccessKeyId}   = $self->id;
    $sign_hash{Timestamp}        = $self->timestamp;
    $sign_hash{Version}          = $self->version;
    $sign_hash{SignatureVersion} = 2;
    $sign_hash{SignatureMethod}  = 'HmacSHA256';

    my @param;
    my @parameter_keys = sort keys %sign_hash;
    for my $p (@parameter_keys) {
	push @param,join '=',map {uri_escape($_,"^A-Za-z0-9\-_.~")} ($p,$sign_hash{$p});
    }
    my $to_sign = join("\n",
		       $action,$host,$path,join('&',@param));
    my $signature = encode_base64(hmac_sha256($to_sign,$self->secret),'');
    $sign_hash{Signature} = $signature;

    my $uri = URI->new($self->endpoint);
    $uri->query_form(\%sign_hash);

    return POST $self->endpoint,[%sign_hash];
}

=head2 @param = $ec2->args(ParamName=>@_)

Set up calls that take either method(-resource_id=>'foo') or method('foo').

=cut

sub args {
    my $self = shift;
    my $default_param_name = shift;
    return unless @_;
    return @_ if $_[0] =~ /^-/;
    return ($default_param_name => \@_);
}

=head1 OTHER INFORMATION

This section contains technical information that may be of interest to developers.

=head2 Signing and authentication protocol

This module uses Amazon AWS signing protocol version 2, as described
at
http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?using-query-api.html. It
uses the HmacSHA256 signature method, which is the most secure method
currently available. For additional security, use "https" for the
communications endpoint:

  $ec2 = VM::EC2->new(-endpoint=>'https://ec2.amazonaws.com');

=head2 Subclassing VM::EC2 objects

To subclass VM::EC2 objects (or implement your own from scratch) you
will need to override the object dispatch mechanism. Fortunately this
is very easy. After "use VM::EC2" call
VM::EC2::Dispatch->add_override() one or more times:

 VM::EC2::Dispatch->add_override($call_name=>\&subroutine).

The first argument is name of the Amazon API call,
e.g. "DescribeImages". The second argument is a CODE reference to the
code you want to be invoked to handle the parsed XML returned from the
request. The code will receive two arguments consisting of the parsed
content of the response, and the VM::EC2 object used to generate the
request.

The parsed content is the result of passing the raw XML through a
XML::Simple object created with:

 XML::Simple->new(ForceArray    => ['item'],
                  KeyAttr       => ['key'],
                  SuppressEmpty => undef);

In general, this will give you a hash of hashes. Any tag named 'item'
will be forced to point to an array reference, and any tag named "key"
will be flattened as described in the XML::Simple documentation.

A simple way to examine the raw parsed XML is to invoke any
VM::EC2::Generic's as_string() method:

 my ($i) = $ec2->describe_instances;
 print $i->as_string;

This will give you a Data::Dumper representation of the XML after it
has been parsed.

=head1 SEE ALSO

L<Net::Amazon::EC2>
L<VM::EC2::Dispatch>
L<VM::EC2::Generic>
L<VM::EC2::BlockDevice>
L<VM::EC2::BlockDevice::Attachment>
L<VM::EC2::BlockDevice::Mapping>
L<VM::EC2::BlockDevice::Mapping::EBS>
L<VM::EC2::ConsoleOutput>
L<VM::EC2::Error>
L<VM::EC2::Generic>
L<VM::EC2::Group>
L<VM::EC2::Image>
L<VM::EC2::Instance>
L<VM::EC2::Instance::Metadata>
L<VM::EC2::Instance::Set>
L<VM::EC2::Instance::State>
L<VM::EC2::Instance::State::Change>
L<VM::EC2::Instance::State::Reason>
L<VM::EC2::KeyPair>
L<VM::EC2::Region>
L<VM::EC2::ReservationSet>
L<VM::EC2::SecurityGroup>
L<VM::EC2::Snapshot>
L<VM::EC2::Tag>
L<VM::EC2::Volume>

=head1 AUTHOR

Lincoln Stein E<lt>lincoln.stein@gmail.comE<gt>.

Copyright (c) 2011 Ontario Institute for Cancer Research

This package and its accompanying libraries is free software; you can
redistribute it and/or modify it under the terms of the GPL (either
version 1, or at your option, any later version) or the Artistic
License 2.0.  Refer to LICENSE for the full license text. In addition,
please see DISCLAIMER.txt for disclaimers of warranty.

=cut


1;