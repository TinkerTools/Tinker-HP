c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     #####################################################################
c     ##                                                                 ##
c     ##  module molcul  --  individual molecules within current system  ##
c     ##                                                                 ##
c     #####################################################################
c
c
c     molmass   molecular weight for each molecule in the system
c     totmass   total weight of all the molecules in the system
c     nmol      total number of separate molecules in the system
c     nmoleloc  local number of separate molecules in the system
c     kmol      contiguous list of the atoms in each molecule
c     imol      first and last atom of each molecule in the list
c     molcule   number of the molecule to which each atom belongs
c
c
      module molcul
      implicit none
      integer nmol,nmoleloc
      integer, pointer :: molcule(:),kmol(:),imol(:,:)
      real*8 totmass
      real*8, pointer :: molmass(:)
      save
      end
