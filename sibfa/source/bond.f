c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ################################################################
c     ##                                                            ##
c     ##  module bond  --  covalent bonds in the current structure  ##
c     ##                                                            ##
c     ################################################################
c
c
c     bk      bond stretch force constants (kcal/mole/Ang**2)
c     bl      ideal bond length values in Angstroms
c     nbond   total number of bond stretches in the system
c     nbondloc   local number of bond stretches in the system
c     nbondbloc   local+neighbors number of bond stretches in the system
c     nbondlocnl   localnl number of bond stretches in the system
c     ibnd    numbers of the atoms in each bond stretch
c
c
      module bond
      implicit none
      integer nbond,nbondloc,nbondbloc,nbondlocnl
      integer, pointer :: ibnd(:,:)
      integer, allocatable :: bondlocnl(:)
      real*8, pointer ::  bk(:),bl(:)
      save
      end
