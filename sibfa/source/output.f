c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ###################################################################
c     ##                                                               ##
c     ##  module output  --  control of coordinate output file format  ##
c     ##                                                               ##
c     ###################################################################
c
c
c     archive    logical flag to save structures in an archive
c     noversion  logical flag governing use of filename versions
c     overwrite  logical flag to overwrite intermediate files inplace
c     cyclesave  logical flag to mark use of numbered cycle files
c     coordtype  selects Cartesian, internal, rigid body or none
c
c
      module output
      implicit none
      logical archive,noversion
      logical overwrite,cyclesave
      character*9 coordtype
      save
      end
