bootstrap-windows
=================

Provision and Bootstrap Windows EC2 Instances With Chef on OSX

When using the script at http://scottwb.com/blog/2012/12/13/provision-and-bootstrap-windows-ec2-instances-with-chef/ to bootstrap windows nodes on ec2 a bug appears.

The following commit on knife-windows https://github.com/opscode/knife-windows/commit/8e81e844158f759ffb602b0eee1f8f22effa6b44 introduces the ' sign that gets encoded in a strange way when running the script on OSX and prevents the chef msi client to be downloaded. The bug is currently reported at https://tickets.opscode.com/browse/KNIFE-379.

This is a modification of the bootstrap-windows.rb script that mitigates that issue by using the wget.ps1 script for Powershell to download the msi file instead. 

Note that just running with knife-windows 0.5.10 also presents an error, namely the "CScript Error: Execution > of the Windows Script Host failed. (0x800A0007)" as described at http://lists.opscode.com/sympa/arc/chef/2013-05/msg00322.html.


USAGE
===
Modify the parameters inside the script prior to running it.
Use only knife-windows 0.5.10.
