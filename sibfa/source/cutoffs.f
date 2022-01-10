c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ################################################################
c     ##                                                            ##
c     ##  subroutine cutoffs  --  set distance                      ##
c     ##                                                            ##
c     ################################################################
c
c
c     "cutoffs" initializes and stores spherical energy cutoff
c     distance windows and Ewald sum cutoffs,
c     and the pairwise neighbor generation method
c
c
      subroutine cutoffs
      use bound
      use cutoff
      use domdec
      use keys
      use iounit
      use neigh
      implicit none
      integer i,next
      real*8 big,value
      logical truncate
      character*20 keyword
      character*120 record
      character*120 string
c
c
c     set defaults for spherical energy cutoff distances
c
      big = 1.0d12
      vdwcut = 9.0d0
      chgcut = 9.0d0
      mpolecut = 9.0d0
      ewaldcut = 7.0d0
      ddcut = 0.0d0
      repcut = 9.0d0
      dispcut = 9.0d0
      ctransfercut = 7.0d0
      mpolectcut = 4.0d0
c
c     set defaults for tapering, neighbor buffers
c
      vdwtaper = 0.90d0
      disptaper = 0.90d0
      chgtaper = 0.65d0
      mpoletaper = 0.65d0
      lbuffer = 2.0d0
c
c     set defaults for Ewald sum, tapering style and neighbor method
c
      use_ewald = .false.
      truncate = .false.
      use_list = .true.
      use_vlist = .true.
      use_mlist = .true.
      use_clist = .true.
      use_replist = .false.
      use_displist = .false.
      use_ctransferlist = .false.
c
c      set default for neighbor list update, reference = 20 for a 2fs time step
c
      ineigup = 20
c
c     search the keywords for various cutoff parameters
c
      do i = 1, nkey
         next = 1
         record = keyline(i)
         call gettext (record,keyword,next)
         call upcase (keyword)
         string = record(next:120)
c
c     get values related to use of Ewald summation
c
         if (keyword(1:6) .eq. 'EWALD ') then
            use_ewald = .true.
         else if (keyword(1:13) .eq. 'EWALD-CUTOFF ') then
            read (string,*,err=10,end=10)  ewaldcut

c     get values for the tapering style and neighbor method
c
         else if (keyword(1:9) .eq. 'TRUNCATE ') then
            truncate = .true.
c
c     get the cutoff radii for potential energy functions
c
         else if (keyword(1:7) .eq. 'CUTOFF ') then
            read (string,*,err=10,end=10)  value
            vdwcut = value
            mpolecut = value
            ewaldcut = value
         else if (keyword(1:11) .eq. 'VDW-CUTOFF ') then
            read (string,*,err=10,end=10)  vdwcut
         else if (keyword(1:11) .eq. 'CHG-CUTOFF ') then
            read (string,*,err=10,end=10)  chgcut
         else if (keyword(1:13) .eq. 'MPOLE-CUTOFF ') then
            read (string,*,err=10,end=10)  mpolecut
         else if (keyword(1:11) .eq. 'REP-CUTOFF ') then
            read (string,*,err=10,end=10)  repcut
         else if (keyword(1:12) .eq. 'DISP-CUTOFF ') then
            read (string,*,err=10,end=10)  dispcut
         else if (keyword(1:17) .eq. 'CTRANSFER-CUTOFF ') then
            read (string,*,err=10,end=10)  ctransfercut
         else if (keyword(1:17) .eq. 'MPOLECT-CUTOFF ') then
            read (string,*,err=10,end=10)  mpolectcut
c
c     get distance for initialization of energy switching
c
         else if (keyword(1:6) .eq. 'TAPER ') then
            read (string,*,err=10,end=10)  value
            vdwtaper = value
            chgtaper = value
            mpoletaper = value
         else if (keyword(1:10) .eq. 'VDW-TAPER ') then
            read (string,*,err=10,end=10)  vdwtaper
         else if (keyword(1:11) .eq. 'DISP-TAPER ') then
            read (string,*,err=10,end=10)  disptaper
         else if (keyword(1:12) .eq. 'MPOLE-TAPER ') then
            read (string,*,err=10,end=10)  mpoletaper
c
c     get buffer width for use with pairwise neighbor lists
c
         else if (keyword(1:12) .eq. 'LIST-BUFFER ') then
            read (string,*,err=10,end=10)  lbuffer
         end if
   10    continue
      end do
c
c     keyword to include another (bigger than the non bonded ones) cutoff in the
c     spatial decomposition. This will add the processes within this cutoff in the
c     communication routines: positions, indexes, forces
c
      do i = 1, nkey
         next = 1
         record = keyline(i)
         call upcase (record)
         call gettext (record,keyword,next)
         string = record(next:120)
         if (keyword(1:15) .eq. 'DD-CUTOFF ') then
            read (string,*,err=100,end=100)  ddcut
            if (rank.eq.0) write(iout,1000) ddcut
         end if
 1000    format (/,' Additional cutoff for spatial decompostion: ',
     $     F14.5)
  100    continue
      end do
c
c     return an error if PME is not used
c
      if (.not.(use_ewald)) then
        if (rank.eq.0) 
     $   write(*,*) 'This program is only compatible with PME'
        call fatal
      end if
c
c     apply any Ewald cutoff to charge and multipole terms
c
      if (use_ewald) then
         mpolecut = ewaldcut
         chgcut = ewaldcut
      end if
c
c     convert any tapering percentages to absolute distances
c
      if (vdwtaper .lt. 1.0d0)  vdwtaper = vdwtaper * vdwcut
      if (disptaper .lt. 1.0d0)  disptaper = disptaper * dispcut
      if (mpoletaper .lt. 1.0d0)  mpoletaper = mpoletaper * mpolecut
      if (chgtaper .lt. 1.0d0)  chgtaper = chgtaper * chgcut
c
c     apply truncation cutoffs if they were requested
c
      if (truncate) then
         vdwtaper = big
         chgtaper = big
         mpoletaper = big
      end if
c
c     set buffer region limits for pairwise neighbor lists
c
      lbuf2 = (0.5d0*lbuffer)**2
      vbuf2 = (vdwcut+lbuffer)**2
      cbuf2 = (chgcut+lbuffer)**2
      mbuf2 = (mpolecut+lbuffer)**2
      mpolectbuf2 = (mpolectcut+lbuffer)**2
      repbuf2 = (repcut+lbuffer)**2
      dispbuf2 = (dispcut+lbuffer)**2
      ctransferbuf2 = (ctransfercut+lbuffer)**2
      return
      end
