c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ################################################################
c     ##                                                            ##
c     ##  subroutine kopdist  --  out-of-plane distance parameters  ##
c     ##                                                            ##
c     ################################################################
c
c
c     "kopdist" assigns the force constants for out-of-plane
c     distance at trigonal centers via the central atom height;
c     also processes any new or changed parameter values
c
c
      subroutine kopdist(init)
      use angpot
      use atmlst
      use atmtyp
      use atoms
      use couple
      use domdec
      use inform
      use iounit
      use keys
      use kopdst
      use opdist
      use potent
      implicit none
      integer i,j,k,nopd
      integer ia,ib,ic,id,iglob
      integer ita,itb,itc,itd
      integer imin,itmin
      integer size,next
      integer opdistcount,nopdistloc1
      real*8 fopd
      logical header
      character*4 pa,pb,pc,pd
      character*12 zeros
      character*16 blank
      character*16 pt,pt0
      character*20 keyword
      character*120 record
      character*120 string
      logical init
c
      blank = '                '
      zeros = '000000000000'
      if (init) then
c
c     allocate some arrays
c
        call alloc_shared_opdist
c
c       process keywords containing out-of-plane distance parameters
c
        header = .true.
        do i = 1, nkey
           next = 1
           record = keyline(i)
           call gettext (record,keyword,next)
           call upcase (keyword)
           if (keyword(1:7) .eq. 'OPDIST ') then
              ia = 0
              ib = 0
              ic = 0
              id = 0
              fopd = 0.0d0
              string = record(next:120)
              read (string,*,err=10,end=10)  ia,ib,ic,id,fopd
   10         continue
              size = 4
              call numeral (ia,pa,size)
              call numeral (ib,pb,size)
              call numeral (ic,pc,size)
              call numeral (id,pd,size)
              imin = min(ib,ic,id)
              if (ib .eq. imin) then
                 if (ic .le. id) then
                    pt = pa//pb//pc//pd
                 else
                    pt = pa//pb//pd//pc
                 end if
              else if (ic .eq. imin) then
                 if (ib .le. id) then
                    pt = pa//pc//pb//pd
                 else
                    pt = pa//pc//pd//pb
                 end if
              else if (id .eq. imin) then
                 if (ib .le. ic) then
                    pt = pa//pd//pb//pc
                 else
                    pt = pa//pd//pc//pb
                 end if
              end if
              if (.not. silent) then
                 if (header) then
                    header = .false.
                    if (rank.eq.0) write (iout,20)
   20               format (/,' Additional Out-of-Plane Distance',
     &                         ' Parameters :',
     &                      //,5x,'Atom Classes',19x,'K(OPD)',/)
                 end if
                 if (rank.eq.0) write (iout,30)  ia,ib,ic,id,fopd
   30            format (4x,4i4,10x,2f12.3)
              end if
              do j = 1, maxnopd
                 if (kopd(j).eq.blank .or. kopd(j).eq.pt) then
                    kopd(j) = pt
                    opds(j) = fopd
                    goto 50
                 end if
              end do
              if (rank.eq.0) write (iout,40)
   40         format (/,' KOPDIST  --  Too many Out-of-Plane Distance',
     &                   ' Parameters')
              abort = .true.
   50         continue
           end if
        end do
c
c       determine the total number of forcefield parameters
c
        nopd = maxnopd
        do i = maxnopd, 1, -1
           if (kopd(i) .eq. blank)  nopd = i - 1
        end do
c
c       assign out-of-plane distance parameters for trigonal sites
c
        nopdist = 0
        if (nopd .ne. 0) then
           do i = 1, n
              nbopdist(i) = nopdist
              if (n12(i) .eq. 3) then
                 ia = i
                 ib = i12(1,i)
                 ic = i12(2,i)
                 id = i12(3,i)
                 ita = class(i)
                 itb = class(ib)
                 itc = class(ic)
                 itd = class(id)
                 size = 4
                 call numeral (ita,pa,size)
                 call numeral (itb,pb,size)
                 call numeral (itc,pc,size)
                 call numeral (itd,pd,size)
                 itmin = min(itb,itc,itd)
                 if (itb .eq. itmin) then
                    if (itc .le. itd) then
                       pt = pa//pb//pc//pd
                    else
                       pt = pa//pb//pd//pc
                    end if
                 else if (itc .eq. itmin) then
                    if (itb .le. itd) then
                       pt = pa//pc//pb//pd
                    else
                       pt = pa//pc//pd//pb
                    end if
                 else if (itd .eq. itmin) then
                    if (itb .le. itc) then
                       pt = pa//pd//pb//pc
                    else
                       pt = pa//pd//pc//pb
                    end if
                 end if
                 pt0 = pa//zeros
                 do j = 1, nopd
                    if (kopd(j) .eq. pt) then
                       nopdist = nopdist + 1
                       iopd(1,nopdist) = ia
                       iopd(2,nopdist) = ib
                       iopd(3,nopdist) = ic
                       iopd(4,nopdist) = id
                       opdk(nopdist) = opds(j)
                       goto 60
                    end if
                 end do
                 do j = 1, nopd
                    if (kopd(j) .eq. pt0) then
                       nopdist = nopdist + 1
                       iopd(1,nopdist) = ia
                       iopd(2,nopdist) = ib
                       iopd(3,nopdist) = ic
                       iopd(4,nopdist) = id
                       opdk(nopdist) = opds(j)
                       goto 60
                    end if
                 end do
   60            continue
              end if
           end do
        end if
c
c       mark angles at trigonal sites to use projected in-plane values
c
        do i = 1, nopdist
           ia = iopd(1,i)
           do j = 1, 3
              k = anglist(j,ia)
              if (angtyp(k) .eq. 'HARMONIC')  angtyp(k) = 'IN-PLANE'
           end do
        end do
c
c       turn off out-of-plane distance potential if it is not used
c
        if (nopdist .eq. 0)  use_opdist = .false.
      end if
      if (allocated(opdistglob)) deallocate(opdistglob)
      allocate (opdistglob(n))
c
      nopd = maxnopd
      do i = maxnopd, 1, -1
         if (kopd(i) .eq. blank)  nopd = i - 1
      end do
c
      nopdistloc = 0
      if (nopd .ne. 0) then
         do i = 1, nloc
            iglob = glob(i)
            opdistcount = nbopdist(iglob)
            if (n12(iglob) .eq. 3) then
               ia = i
               ib = i12(1,iglob)
               ic = i12(2,iglob)
               id = i12(3,iglob)
               ita = class(iglob)
               itb = class(ib)
               itc = class(ic)
               itd = class(id)
               size = 4
               call numeral (ita,pa,size)
               call numeral (itb,pb,size)
               call numeral (itc,pc,size)
               call numeral (itd,pd,size)
               itmin = min(itb,itc,itd)
               if (itb .eq. itmin) then
                  if (itc .le. itd) then
                     pt = pa//pb//pc//pd
                  else
                     pt = pa//pb//pd//pc
                  end if
               else if (itc .eq. itmin) then
                  if (itb .le. itd) then
                     pt = pa//pc//pb//pd
                  else
                     pt = pa//pc//pd//pb
                  end if
               else if (itd .eq. itmin) then
                  if (itb .le. itc) then
                     pt = pa//pd//pb//pc
                  else
                     pt = pa//pd//pc//pb
                  end if
               end if
               pt0 = pa//zeros
               nopdistloc1 = 0
               do j = 1, nopd
                  if (kopd(j) .eq. pt) then
                     nopdistloc = nopdistloc + 1
                     nopdistloc1 = nopdistloc1 + 1
                     opdistglob(nopdistloc) = opdistcount + nopdistloc1
                     goto 70
                  end if
               end do
               do j = 1, nopd
                 if (kopd(j) .eq. pt0) then
                     nopdistloc = nopdistloc + 1
                     nopdistloc1 = nopdistloc1 + 1
                     opdistglob(nopdistloc) = opdistcount + nopdistloc1
                     goto 70
                 end if
              end do
   70         continue
           end if
        end do
      end if
c
      return
      end
c
c     subroutine alloc_shared_opdist : allocate shared memory pointers for opdist
c     parameter arrays
c
      subroutine alloc_shared_opdist
      USE, INTRINSIC :: ISO_C_BINDING, ONLY : C_PTR, C_F_POINTER
      use sizes
      use atoms
      use domdec
      use opdist
      use mpi
      implicit none
      integer :: win,win2
      INTEGER(KIND=MPI_ADDRESS_KIND) :: windowsize
      INTEGER :: disp_unit,ierr,total
      TYPE(C_PTR) :: baseptr
      integer :: arrayshape(1),arrayshape2(2)
c
      if (associated(opdk)) deallocate(opdk)
      if (associated(iopd)) deallocate(iopd)
c
c     opdk
c
      arrayshape=(/n/)
      if (hostrank == 0) then
        windowsize = int(n,MPI_ADDRESS_KIND)*8_MPI_ADDRESS_KIND
      else
        windowsize = 0_MPI_ADDRESS_KIND
      end if
      disp_unit = 1
c
c    allocation
c
      CALL MPI_Win_allocate_shared(windowsize, disp_unit, MPI_INFO_NULL,
     $  hostcomm, baseptr, win, ierr)
      if (hostrank /= 0) then
        CALL MPI_Win_shared_query(win, 0, windowsize, disp_unit,
     $  baseptr, ierr)
      end if
c
c    association with fortran pointer
c
      CALL C_F_POINTER(baseptr,opdk,arrayshape)
c
c     iopd
c
      arrayshape2=(/4,n/)
      if (hostrank == 0) then
        windowsize = int(4*n,MPI_ADDRESS_KIND)*4_MPI_ADDRESS_KIND
      else
        windowsize = 0_MPI_ADDRESS_KIND
      end if
      disp_unit = 1
c
c    allocation
c
      CALL MPI_Win_allocate_shared(windowsize, disp_unit, MPI_INFO_NULL,
     $  hostcomm, baseptr, win, ierr)
      if (hostrank /= 0) then
        CALL MPI_Win_shared_query(win, 0, windowsize, disp_unit,
     $  baseptr, ierr)
      end if
c
c    association with fortran pointer
c
      CALL C_F_POINTER(baseptr,iopd,arrayshape2)
      return
      end
