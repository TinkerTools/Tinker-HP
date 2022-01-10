c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ######################################################################
c     ##                                                                  ##
c     ##  module kvdwpr  --  forcefield parameters for special vdw terms  ##
c     ##                                                                  ##
c     ######################################################################
c
c
c     maxnvp   maximum number of special van der Waals pair entries
c
c     radpr    radius parameter for special van der Waals pairs
c     epspr    well depth parameter for special van der Waals pairs
c     kvpr     string of atom classes for special van der Waals pairs
c
c
      module kvdwpr
      implicit none
      integer maxnvp
      parameter (maxnvp=500)
      real*8 radpr(maxnvp),epspr(maxnvp)
      character*8 kvpr(maxnvp)
      save
      end
