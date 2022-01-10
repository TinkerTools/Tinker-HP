c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     #####################################################################
c     ##                                                                 ##
c     ##  module polar  --  polarizabilities and induced dipole moments  ##
c     ##                                                                 ##
c     #####################################################################
c
c
c     polarity  dipole polarizability for each multipole site (Ang**3)
c     thole     Thole polarizability damping value for each site
c     pdamp     value of polarizability scale factor for each site
c     uind      induced dipole components at each multipole site
c     uinp      induced dipoles in field used for energy interactions
c     npolar    total number of polarizable sites in the system
c
c
      module polar
      implicit none
      integer npolar
      real*8, pointer :: polarity(:),thole(:),pdamp(:)
      real*8, allocatable :: uind(:,:),uinp(:,:)
      save
      end
