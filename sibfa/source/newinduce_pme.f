c      
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c      
      subroutine newinduce_pme
      use atmlst
      use domdec
      use ewald
      use iounit
      use math
      use mpole
      use pme
      use polar
      use polpot
      use potent
      use units
      use uprior
      use mpi
      implicit none
c
c     evaluate induced dipole moments and the polarization energy
c     using either a (preconditioned) conjugate gradient algorithm or
c     Jacobi iterations coupled with DIIS extrapolation.
c
      integer i, j, k, nrhs
c
c     MPI
c
      integer ierr, iipole, proc,tag
      integer, allocatable :: reqrecdirsend(:),reqrecdirrec(:)
      integer, allocatable :: reqsend(:),reqrec(:)
      integer, allocatable :: req2send(:),req2rec(:)
      integer status(MPI_STATUS_SIZE)
c
      parameter (nrhs=2)
      real*8  wtime0, wtime1, wtime2, omp_get_wtime, udsum, upsum
      real*8  term, xx(1)
      real*8, allocatable :: ef(:,:,:), mu(:,:,:), murec(:,:,:)
      real*8, allocatable :: cphi(:,:)
c
      real*8, allocatable :: buffermpi(:,:), buffermpimu(:,:,:)
c
      external tmatxb_pme
c
      if (.not.use_polar) return
c
 1000 format(' illegal polalg in newinduce.')
 1010 format(' time for the ',a,F14.5)
 1020 format(' total elapsed time in newinduce: ',F14.5)
c
c     allocate some memory and clear the arrays:
c
c      call MPI_BARRIER(COMM_BEAD,ierr)
c
      if (rank.le.ndir-1) then
        allocate (mu(3,nrhs,max(1,npolebloc)))
        mu = 0.0d0
        allocate (ef(3,nrhs,max(1,npolebloc)))
        ef = 0.0d0
        allocate (cphi(10,max(1,npoleloc)))
        cphi = 0.0d0
        allocate (buffermpi(10,max(npoleloc,1)))
        buffermpi = 0.0d0
        allocate (buffermpimu(3,nrhs,max(npoleloc,1)))
        buffermpimu = 0.0d0
      else
        allocate (murec(3,nrhs,max(npolerecloc,1)))
        murec = 0.0d0
        if (allocated(fphirec)) deallocate (fphirec)
        allocate (fphirec(20,max(npolerecloc,1)))
        fphirec = 0.0d0
        if (allocated(cphirec)) deallocate (cphirec)
        allocate (cphirec(10,max(npolerecloc,1)))
        cphirec = 0.0d0
        allocate (buffermpi(10,max(npolerecloc,1)))
        buffermpi = 0.0d0
        allocate (buffermpimu(3,nrhs,max(npolerecloc,1)))
        buffermpimu = 0.0d0
      end if
c
      allocate (reqrecdirsend(nproc))
      allocate (reqrecdirrec(nproc))
      allocate (reqsend(nproc))
      allocate (reqrec(nproc))
      allocate (req2send(nproc))
      allocate (req2rec(nproc))
c
c     compute the electric fields:
c
c$    wtime0 = omp_get_wtime()
c
c     MPI : begin reception
c
      if (rank.le.ndir-1) then
        do i = 1, n_recep1
          tag = nproc*rank + p_recep1(i) + 1
          call MPI_IRECV(mu(1,1,bufbegpole(p_recep1(i)+1)),
     $     3*nrhs*domlen(p_recep1(i)+1),MPI_REAL8,p_recep1(i),tag,
     $     COMM_BEAD,reqrec(i),ierr)
        end do
      end if
c
c     Begin the reception of the reciprocal fields
c
      if (rank.le.ndir-1) then
        do i = 1, nrecdir_send1
          proc = precdir_send1(i)
          tag = nproc*rank + proc + 1
          call MPI_IRECV(buffermpi(1,bufbeg1(proc+1)),
     $     10*buflen1(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $     reqrecdirrec(i),ierr)
        end do
      else
c
c    compute the reciprocal space contribution (fields)
c
        call efld0_recip
c
        do i = 1, nrecdir_recep1
          proc = precdir_recep1(i)
          tag = nproc*proc + rank + 1
          do j = 0, buflen2(proc+1)-1
            call amove(10,cphirec(1,polerecloc(
     $        buf2(bufbeg2(proc+1)+j))),buffermpi(1,bufbeg2(proc+1)+j))
          end do
          call MPI_ISEND(buffermpi(1,bufbeg2(proc+1)),
     $    10*buflen2(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $    reqrecdirsend(i),ierr)
        end do
c
        do i = 1, nrecdir_recep1
          proc = precdir_recep1(i)
          call MPI_WAIT(reqrecdirsend(i),status,ierr)
        end do
      end if
c
c    The real space processes compute the real fields and  add them to the recip ones
c
      if (rank.le.ndir-1) then
        term = (4.0d0/3.0d0) * aewald**3 / sqrtpi
c
        call efld0_direct(nrhs,ef)
        call commfield(nrhs,ef)
c
        do i = 1, nrecdir_send1
          proc = precdir_send1(i)
          call MPI_WAIT(reqrecdirrec(i),status,ierr)
          do j = 0, buflen1(proc+1)-1
            call amove(10,buffermpi(1,bufbeg1(proc+1)+j),
     $        cphi(1,poleloc(buf1(bufbeg1(proc+1)+j))))
          end do
        end do
c
c       Add direct and reciprocal fields
c
        do i = 1, npoleloc
          iipole = poleglob(i)
          do j = 1, 3
            ef(j,1,i)  = ef(j,1,i) - cphi(j+1,i) +
     $        term*rpole(j+1,iipole)
            ef(j,2,i)  = ef(j,2,i) - cphi(j+1,i) +
     $        term*rpole(j+1,iipole)
          end do
        end do
      end if
c$    wtime1 = omp_get_wtime()
c
c     guess the dipoles:
c
c     predicted values for always stable predictor-corrector method
c
      if (rank.le.ndir-1) then
       if (use_pred .and. nualt.eq.maxualt) then
         call ulspred
         do i = 1, npoleloc
           iipole = poleglob(i)
           do j = 1, 3
             udsum = 0.0d0
             upsum = 0.0d0
             do k = 1, nualt - 1
               udsum = udsum + bpred(k)*udalt(k,j,iipole)
               upsum = upsum + bpred(k)*upalt(k,j,iipole)
             end do
             mu(j,1,i) = udsum
             mu(j,2,i) = upsum
           end do
         end do
       else if (polgsf.eq.0) then
         do i = 1, npoleloc
           iipole = poleglob(i)
           do k = 1, nrhs
             do j = 1, 3
               mu(j,k,i) = polarity(iipole)*ef(j,k,i)
             end do
           end do
         end do
       else
         do i = 1, npoleloc
           iipole = poleglob(i)
           do j = 1, 3
             mu(j,1,i) = uind(j,iipole)
             mu(j,2,i) = uinp(j,iipole)
           end do
         end do
       end if
c
c     MPI : begin sending
c
c      to direct processes
c
       do i = 1, n_send1
         tag = nproc*p_send1(i) + rank + 1
         call MPI_ISEND(mu,3*nrhs*npoleloc,
     $    MPI_REAL8,p_send1(i),tag,COMM_BEAD,
     $    reqsend(i),ierr)
       end do
c
c      to PME processes
c
        do i = 1, nrecdir_send1
          proc = precdir_send1(i)
          tag = nproc*proc + rank +1
          do j = 0, buflen1(proc+1)-1
            call amove(3*nrhs,mu(1,1,poleloc(buf1(bufbeg1(proc+1)+j))),
     $        buffermpimu(1,1,bufbeg1(proc+1)+j))
          end do
          call MPI_ISEND(buffermpimu(1,1,bufbeg1(proc+1)),
     $    3*nrhs*buflen1(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $    req2send(i),ierr)
        end do
c
       do i = 1, n_recep1
         call MPI_WAIT(reqrec(i),status,ierr)
       end do
       do i = 1, n_send1
         call MPI_WAIT(reqsend(i),status,ierr)
       end do
       do i = 1, nrecdir_send1
         proc = precdir_send1(i)
         call MPI_WAIT(req2send(i),status,ierr)
       end do
      else
c
c     Reception of predicted mu by the PME processes
c
        do i = 1, nrecdir_recep1
          proc = precdir_recep1(i)
          tag = nproc*rank + proc + 1
          call MPI_IRECV(buffermpimu(1,1,bufbeg2(proc+1)),
     $     3*nrhs*buflen2(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $     req2rec(i),ierr)
        end do
        do i = 1, nrecdir_recep1
          proc = precdir_recep1(i)
          call MPI_WAIT(req2rec(i),status,ierr)
          do j = 0, buflen2(proc+1)-1
            call amove(3*nrhs,buffermpimu(1,1,bufbeg2(proc+1)+j),
     $        murec(1,1,polerecloc(buf2(bufbeg2(proc+1)+j))))
          end do
        end do
      end if
c
c     now, call the proper solver.
c
      if (polalg.eq.1) then
        if (rank.le.ndir-1) then
          call inducepcg_pme(tmatxb_pme,nrhs,.true.,ef,mu,xx)
        else
          call inducepcg_pme(tmatxb_pme,nrhs,.true.,xx,xx,murec)
        end if
      else if (polalg.eq.2) then
        if (rank.le.ndir-1) then
          call inducejac_pme(tmatxb_pme,nrhs,.true.,ef,mu,xx)
       else
          call inducejac_pme(tmatxb_pme,nrhs,.true.,xx,xx,murec)
       end if
      else 
         if (rank.eq.0) write(iout,1000) 
         call fatal
      end if
c$    wtime2 = omp_get_wtime()
      if (polprt.ge.1.and.rank.eq.0) then
        if (polprt.ge.2) then
          write(iout,1010) 'fields:  ', wtime1-wtime0
          write(iout,1010) 'dipoles: ', wtime2-wtime1
        end if
        write(iout,1020) wtime2 - wtime0
      end if
c
c     move the computed dipoles in the common block.
c
      if (rank.le.ndir-1) then
        do i = 1, npolebloc
          iipole = poleglob(i)
          do j = 1, 3
            uind(j,iipole) = mu(j,1,i)
            uinp(j,iipole) = mu(j,2,i)
          end do
        end do
      else
        do i = 1, npolerecloc
          iipole = polerecglob(i)
          do j = 1, 3
            uind(j,iipole) = murec(j,1,i)
            uinp(j,iipole) = murec(j,2,i)
          end do
        end do
      end if
      deallocate (buffermpi)
      deallocate (buffermpimu)
      if (rank.le.ndir-1) then
        deallocate (ef)
        deallocate (cphi)
        deallocate (mu)
      else
c        deallocate (fphi)
c        deallocate (cphirec)
        deallocate (murec)
      end if
      deallocate (reqrec)
      deallocate (reqsend)
      deallocate (req2send)
      deallocate (req2rec)
      deallocate (reqrecdirrec)
      deallocate (reqrecdirsend)
c
c     update the lists of previous induced dipole values
c
      if (use_pred) then
         if (rank.le.ndir-1) then
           nualt = min(nualt+1,maxualt)
           do i = 1, npolebloc
              iipole = poleglob(i)
              do j = 1, 3
                 do k = nualt, 2, -1
                    udalt(k,j,iipole) = udalt(k-1,j,iipole)
                    upalt(k,j,iipole) = upalt(k-1,j,iipole)
                 end do
                 udalt(1,j,iipole) = uind(j,iipole)
                 upalt(1,j,iipole) = uinp(j,iipole)
               end do
           end do
         end if
      end if
      return
      end
c
      subroutine inducepcg_pme(matvec,nrhs,precnd,ef,mu,murec)
      use atmlst
      use domdec
      use ewald
      use iounit
      use math
      use mpole
      use polar
      use polpot
      use timestat
      use units
      use mpi
      implicit none
c
c     solves the polarizable dipoles linear equations by preconditioned
c     conjugate gradient. A diagonal preconditioner is used when precnd
c     is true, otherwise the standard conjugate gradient algorithm is
c     recovered by setting the preconditioner to one.
c
      integer nrhs
      real*8  ef(3,nrhs,*), mu(3,nrhs,*), murec(3,nrhs,*)
      logical precnd
      real*8, allocatable :: res(:,:,:), h(:,:,:), pp(:,:,:), zr(:,:,:),
     $  diag(:)
      integer i, iglob, it, j, k, iipole
      real*8  ggold(2), ggnew(2), gnorm(2), gg(2), alphacg(2), ene(2)
      real*8  zero, pt5, one, resnrm
      save    zero, pt5, one
      data    zero/0.0d0/, pt5/0.50d0/, one/1.0d0/
      external matvec
      real*8, allocatable :: dipfield(:,:,:),dipfieldbis(:,:,:)
      real*8 term
      real*8 time0,time1
c
c     MPI
c
      real*8, allocatable :: buffermpi1(:,:,:),buffermpi2(:,:,:)
      real*8, allocatable :: buffermpimu(:,:,:)
      integer ierr, tag, proc
      integer req1, req2, req3, req4
      integer,allocatable :: reqrecdirrec(:),reqrecdirsend(:)
      integer,allocatable :: reqendrec(:),reqendsend(:)
      integer,allocatable :: req2endrec(:),req2endsend(:)
      integer,allocatable :: reqrec(:),reqsend(:)
      integer,allocatable :: req2rec(:),req2send(:)
      integer status(MPI_STATUS_SIZE)
c
 1000 format(' cgiter converged after ',I3,' iterations.',/,
     $       ' final energy        = ',2D14.7,/,
     $       ' final residual norm = ',2D14.7)
 1010 format(' energy and residual norm at iteration ',I3,':',4D12.2)
 1020 format(' Conjugate gradient solver: induced dipoles',/,
     $  ' ipole       mux         muy         muz')
 1021 format(' Conjugate gradient solver: induced p-dipoles',/,
     $  ' ipole       mux         muy         muz')
 1030 format(i6,2x,f10.7,2x,f10.7,2x,f10.7)
 1040 format(' Using a diagonal preconditioner.')
c
c
c     allocate some memory and setup the preconditioner:
c
      if (rank.le.ndir-1) then
        allocate (buffermpi1(3,nrhs,max(npoleloc,1)))
        buffermpi1 = 0.0d0
        allocate (buffermpimu(3,nrhs,max(npoleloc,1)))
        buffermpimu = 0.0d0
        allocate (dipfield(3,nrhs,max(1,npoleloc)))
        dipfield = 0d0
        allocate (res(3,nrhs,max(1,npoleloc)))
        allocate (zr(3,nrhs,max(1,npoleloc)))
        allocate (diag(npoleloc))
        allocate (h(3,nrhs,max(1,npolebloc)))
        allocate (pp(3,nrhs,max(1,npolebloc)))
      else
        allocate (buffermpi2(3,nrhs,max(1,npolerecloc)))
        buffermpi2 = 0.0d0
        allocate (buffermpimu(3,nrhs,max(1,npolerecloc)))
        buffermpimu = 0.0d0
        allocate (dipfieldbis(3,nrhs,max(1,npolerecloc)))
        dipfieldbis = 0d0
      end if
      allocate (reqrecdirrec(nproc))
      allocate (reqrecdirsend(nproc))
      allocate (reqrec(nproc))
      allocate (reqsend(nproc))
      allocate (req2rec(nproc))
      allocate (req2send(nproc))
      allocate (reqendrec(nproc))
      allocate (reqendsend(nproc))
      allocate (req2endsend(nproc))
      allocate (req2endrec(nproc))
      if (precnd.and.rank.le.ndir-1) then
        do i = 1, npoleloc
          iipole = poleglob(i)
          diag(i) = polarity(iipole)
        end do
        if (polprt.ge.2.and.rank.eq.0) write (iout,1040)
      else if (rank.le.ndir-1) then
        diag = 1d0
      end if
c
c     initialize
c
      if (rank.le.ndir-1) then
        pp = 0.0d0
        h  = 0.0d0
        res  = 0.0d0
      end if
c
c     now, compute the initial direction
c
      ggold = 0.0d0
c
c     MPI : begin reception
c
      if (rank.le.ndir-1) then
        do i = 1, n_recep1
          tag = nproc*rank + p_recep1(i) + 1
          call MPI_IRECV(pp(1,1,bufbegpole(p_recep1(i)+1)),
     $     3*nrhs*domlen(p_recep1(i)+1),MPI_REAL8,p_recep1(i),tag,
     $     COMM_BEAD,reqrec(i),ierr)
        end do
c
c      Begin the reception of the reciprocal fields
c
        do i = 1, nrecdir_send1
          proc  = precdir_send1(i)
          tag = nproc*rank + proc + 1
         call MPI_IRECV(buffermpi1(1,1,bufbeg1(proc+1)),
     $     3*nrhs*buflen1(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $     reqrecdirrec(i),ierr)
        end do
c
c     The PME processes compute the reciprocal matrix vector product
c
      else
        do i = 1, nrecdir_recep1
          proc = precdir_recep1(i)
          tag = nproc*rank + proc  + 1
         call MPI_IRECV(buffermpimu(1,1,bufbeg2(proc+1)),
     $     3*nrhs*buflen2(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $     req2rec(i),ierr)
        end do
c
        time0 = mpi_wtime()
        call tmatxbrecip(murec,nrhs,dipfieldbis)
        time1 = mpi_wtime()
        timerecdip = timerecdip + time1-time0
        do i = 1, nrecdir_recep1
          proc = precdir_recep1(i)
          tag = nproc*proc + rank + 1
          do j = 0, buflen2(proc+1)-1
            call amove(3*nrhs,dipfieldbis(1,1,polerecloc(
     $        buf2(bufbeg2(proc+1)+j))),
     $        buffermpi2(1,1,bufbeg2(proc+1)+j))
          end do
          call MPI_ISEND(buffermpi2(1,1,bufbeg2(proc+1)),
     $      3*nrhs*buflen2(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $      reqrecdirsend(i),ierr)
        end do
        do i = 1, nrecdir_recep1
          call MPI_WAIT(reqrecdirsend(i),status,ierr)
        end do
      end if
      if (rank.le.ndir-1) then
c
        time0 = mpi_wtime()
        call matvec(nrhs,.true.,mu,h)
        time1 = mpi_wtime()
        timerealdip = timerealdip + time1-time0
        call commfield(nrhs,h)
c
        do i = 1, nrecdir_send1
          proc = precdir_send1(i)
          call MPI_WAIT(reqrecdirrec(i),status,ierr)
          do j = 0, buflen1(proc+1)-1
            call amove(3*nrhs,buffermpi1(1,1,bufbeg1(proc+1)+j),
     $        dipfield(1,1,poleloc(buf1(bufbeg1(proc+1)+j))))
          end do
        end do
        term = (4.0d0/3.0d0) * aewald**3 / sqrtpi
        h(:,:,1:npoleloc) = h(:,:,1:npoleloc)+dipfield(:,:,1:npoleloc)
     $  - term*mu(:,:,1:npoleloc)
        res(:,:,1:npoleloc) = ef(:,:,1:npoleloc)-h(:,:,1:npoleloc)
        do k = 1, nrhs
          do j = 1, 3
            zr(j,k,1:npoleloc) = diag(1:npoleloc)*res(j,k,1:npoleloc)
          end do
        end do
        pp(:,:,1:npoleloc) = zr(:,:,1:npoleloc)
        do k = 1, nrhs
          ggold(k) = sum(res(:,k,:)*zr(:,k,:))
        end do
        call MPI_IALLREDUCE(MPI_IN_PLACE,ggold(1),nrhs,MPI_REAL8,
     $     MPI_SUM,comm_dir,req1,ierr)
c
c     MPI : begin sending to other direct processes
c
        do i = 1, n_send1
          tag = nproc*p_send1(i) + rank + 1
          call MPI_ISEND(pp,3*nrhs*npoleloc,MPI_REAL8,p_send1(i),tag,
     $     COMM_BEAD,reqsend(i),ierr)
        end do
c
c     MPI : begin sending to PME processes
c
        do i = 1, nrecdir_send1
          proc = precdir_send1(i)
          tag = nproc*proc + rank + 1
          do j = 0, buflen1(proc+1)-1
            call amove(3*nrhs,pp(1,1,poleloc(buf1(bufbeg1(proc+1)+j))),
     $        buffermpimu(1,1,bufbeg1(proc+1)+j))
          end do
          call MPI_ISEND(buffermpimu(1,1,bufbeg1(proc+1)),
     $    3*nrhs*buflen1(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $    req2send(i),ierr)
        end do
c
        do i = 1, n_recep1
          call MPI_WAIT(reqrec(i),status,ierr)
        end do
        do i = 1, n_send1
          call MPI_WAIT(reqsend(i),status,ierr)
        end do
c
        do i = 1, nrecdir_send1
          call MPI_WAIT(req2send(i),status,ierr)
        end do
        call MPI_WAIT(req1,status,ierr)
c
      else
        do i = 1, nrecdir_recep1
          proc = precdir_recep1(i)
          call MPI_WAIT(req2rec(i),status,ierr)
          do j = 0, buflen2(proc+1)-1
            call amove(3*nrhs,buffermpimu(1,1,bufbeg2(proc+1)+j),
     $        murec(1,1,polerecloc(buf2(bufbeg2(proc+1)+j))))
          end do
        end do
      end if
c
c     now, start the main loop:
c
      do it = 1, politer
        do k = 1, nrhs
          gg(k) = zero
          ggnew(k) = zero
        end do
c
c     MPI : begin reception
c
        if (rank.le.ndir-1) then
          do i = 1, n_recep1
            tag = nproc*rank + p_recep1(i) + 1
            call MPI_IRECV(pp(1,1,bufbegpole(p_recep1(i)+1)),
     $       3*nrhs*domlen(p_recep1(i)+1),MPI_REAL8,p_recep1(i),tag,
     $       COMM_BEAD,reqrec(i),ierr)
          end do
        else
          do i = 1, nrecdir_recep1
            proc = precdir_recep1(i)
            tag = nproc*rank + proc + 1
           call MPI_IRECV(buffermpimu(1,1,bufbeg2(proc+1)),
     $      3*nrhs*buflen2(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $      req2rec(i),ierr)
          end do
        end if
c
c      Begin the reception of the reciprocal fields
c
        if (rank.le.ndir-1) then
          do i = 1, nrecdir_send1
            proc = precdir_send1(i)
            tag = nproc*rank + proc + 1
            call MPI_IRECV(buffermpi1(1,1,bufbeg1(proc+1)),
     $       3*nrhs*buflen1(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $       reqrecdirrec(i),ierr)
          end do
c
c     The PME processes compute the reciprocal matrix vector product
c
        else
          call tmatxbrecip(murec,nrhs,dipfieldbis)
          do i = 1, nrecdir_recep1
            proc = precdir_recep1(i)
            tag = nproc*proc + rank + 1
            do j = 0, buflen2(proc+1)-1
              call amove(3*nrhs,dipfieldbis(1,1,polerecloc(
     $          buf2(bufbeg2(proc+1)+j))),
     $          buffermpi2(1,1,bufbeg2(proc+1)+j))
            end do
            call MPI_ISEND(buffermpi2(1,1,bufbeg2(proc+1)),
     $        3*nrhs*buflen2(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $        reqrecdirsend(i),ierr)
          end do
          do i = 1, nrecdir_recep1
            call MPI_WAIT(reqrecdirsend(i),status,ierr)
          end do
        end if
        if (rank.le.ndir-1) then
c
          call matvec(nrhs,.true.,pp,h)
          call commfield(nrhs,h)
c
          do i = 1, nrecdir_send1
            proc = precdir_send1(i)
            call MPI_WAIT(reqrecdirrec(i),status,ierr)
            do j = 0, buflen1(proc+1)-1
              call amove(3*nrhs,buffermpi1(1,1,bufbeg1(proc+1)+j),
     $          dipfield(1,1,poleloc(buf1(bufbeg1(proc+1)+j))))
            end do
          end do
c
          h(:,:,1:npoleloc) = h(:,:,1:npoleloc)+dipfield(:,:,1:npoleloc)
     $     - term*pp(:,:,1:npoleloc)
          do k = 1, nrhs
            gg(k) = sum(pp(:,k,1:npoleloc)*h(:,k,1:npoleloc))
          end do
          call MPI_IALLREDUCE(MPI_IN_PLACE,gg(1),nrhs,MPI_REAL8,MPI_SUM,
     $      comm_dir,req2,ierr)
          call MPI_WAIT(req2,status,ierr)
          do k = 1, nrhs
            if (gg(k).eq.zero) return
            alphacg(k)  = ggold(k)/gg(k)
            ggnew(k)  = zero
            ene(k)    = zero
          end do
          do k = 1, nrhs
            mu(:,k,1:npoleloc) = mu(:,k,1:npoleloc) + alphacg(k)*
     $       pp(:,k,1:npoleloc)
            res(:,k,1:npoleloc) = res(:,k,1:npoleloc) - alphacg(k)*
     $       h(:,k,1:npoleloc)
          end do
          do k = 1, nrhs
            do j = 1, 3
              zr(j,k,1:npoleloc) = diag(1:npoleloc)*res(j,k,1:npoleloc)
            end do
          end do
          do k = 1, nrhs
            ggnew(k) = sum(res(:,k,:)*zr(:,k,:))
            ene(k) = -pt5*sum(mu(:,k,1:npoleloc)*(res(:,k,1:npoleloc)+
     $        ef(:,k,1:npoleloc)))
          end do
        end if
        call MPI_IALLREDUCE(MPI_IN_PLACE,ggnew(1),nrhs,MPI_REAL8,
     $      MPI_SUM,COMM_BEAD,req3,ierr)
        call MPI_WAIT(req3,status,ierr)
        if (rank.le.ndir-1) then
          call MPI_IALLREDUCE(MPI_IN_PLACE,ene(1),nrhs,MPI_REAL8,
     $      MPI_SUM,comm_dir,req4,ierr)
          call MPI_WAIT(req4,status,ierr)
          do k = 1, nrhs
            pp(:,k,1:npoleloc) = zr(:,k,1:npoleloc)+ggnew(k)/ggold(k)*
     $         pp(:,k,1:npoleloc)
          end do
c
c     MPI : begin sending to other direct processes
c
          do i = 1, n_send1
            tag = nproc*p_send1(i) + rank + 1
            call MPI_ISEND(pp,3*nrhs*npoleloc,MPI_REAL8,p_send1(i),tag,
     $       COMM_BEAD,reqsend(i),ierr)
          end do
c
c     MPI : begin sending to PME processes
c
          do i = 1, nrecdir_send1
            proc = precdir_send1(i)
            tag = nproc*proc + rank + 1
            do j = 0, buflen1(proc+1)-1
              call amove(3*nrhs,pp(1,1,poleloc(
     $          buf1(bufbeg1(proc+1)+j))),
     $          buffermpimu(1,1,bufbeg1(proc+1)+j))
            end do
            call MPI_ISEND(buffermpimu(1,1,bufbeg1(proc+1)),
     $      3*nrhs*buflen1(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $      req2send(i),ierr)
          end do
c
          do i = 1, n_recep1
            call MPI_WAIT(reqrec(i),status,ierr)
          end do
          do i = 1, n_send1
            call MPI_WAIT(reqsend(i),status,ierr)
          end do
c
          do i = 1, nrecdir_send1
            proc = precdir_send1(i)
            call MPI_WAIT(req2send(i),status,ierr)
          end do
        else
          do i = 1, nrecdir_recep1
            proc = precdir_recep1(i)
            call MPI_WAIT(req2rec(i),status,ierr)
            do j = 0, buflen2(proc+1)-1
              call amove(3*nrhs,buffermpimu(1,1,bufbeg2(proc+1)+j),
     $          murec(1,1,polerecloc(buf2(bufbeg2(proc+1)+j))))
            end do
          end do
        end if
c
        ggold = ggnew
        resnrm = zero
        do k = 1, nrhs
          gnorm(k) = sqrt(ggnew(k)/dble(3*npolar))
          resnrm   = max(resnrm,gnorm(k))
        end do
        if (resnrm.lt.poleps) then
          if (polprt.ge.1.and.rank.eq.0) write(iout,1000) it,
     $      (ene(k)*coulomb, k = 1, nrhs), (gnorm(k), k = 1, nrhs)
          goto 10
        end if
        if (polprt.ge.2.and.rank.eq.0) write(iout,1010)
     $    it, (ene(k)*coulomb, gnorm(k), k = 1, nrhs)
      end do
 10   continue
c
c     MPI : begin reception
c
      if (rank.le.ndir-1) then
        do i = 1, n_recep1
          tag = nproc*rank + p_recep1(i) + 1
          call MPI_IRECV(mu(1,1,bufbegpole(p_recep1(i)+1)),
     $     3*nrhs*domlen(p_recep1(i)+1),MPI_REAL8,p_recep1(i),tag,
     $     COMM_BEAD,reqendrec(i),ierr)
        end do
c
c     MPI : begin sending to other direct processes
c
        do i = 1, n_send1
          tag = nproc*p_send1(i) + rank + 1
          call MPI_ISEND(mu,3*nrhs*npoleloc,MPI_REAL8,p_send1(i),tag,
     $     COMM_BEAD,reqendsend(i),ierr)
        end do
c
c     MPI : begin sending to PME processes
c
        do i = 1, nrecdir_send1
          proc = precdir_send1(i)
          tag = nproc*proc + rank + 1
          do j = 0, buflen1(proc+1)-1
            call amove(3*nrhs,mu(1,1,poleloc(buf1(bufbeg1(proc+1)+j))),
     $        buffermpimu(1,1,bufbeg1(proc+1)+j))
          end do
          call MPI_ISEND(buffermpimu(1,1,bufbeg1(proc+1)),
     $      3*nrhs*buflen1(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $      req2endsend(i),ierr)
        end do
c
        do i = 1, n_recep1
          call MPI_WAIT(reqendrec(i),status,ierr)
        end do
        do i = 1, n_send1
          call MPI_WAIT(reqendsend(i),status,ierr)
        end do
c
        do i = 1, nrecdir_send1
          call MPI_WAIT(req2endsend(i),status,ierr)
        end do
      else
        do i = 1, nrecdir_recep1
          proc = precdir_recep1(i)
          tag = nproc*rank + proc + 1
          call MPI_IRECV(buffermpimu(1,1,bufbeg2(proc+1)),
     $     3*nrhs*buflen2(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $      req2endrec(i),ierr)
        end do
        do i = 1, nrecdir_recep1
          proc = precdir_recep1(i)
          call MPI_WAIT(req2endrec(i),status,ierr)
          do j = 0, buflen2(proc+1)-1
            call amove(3*nrhs,buffermpimu(1,1,bufbeg2(proc+1)+j),
     $        murec(1,1,polerecloc(buf2(bufbeg2(proc+1)+j))))
          end do
        end do
      end if
c
c     finalize and debug printing:
c
      if (polprt.ge.3) then
        write(iout,1020)
        do i = 1, npoleloc
          iglob = glob(i)
          write(iout,1030) iglob, (mu(j,1,i), j = 1, 3)
        end do
      end if
      if (polprt.ge.4) then
        write(iout,1021)
        do i = 1, npoleloc
          iglob = glob(i)
          write(iout,1030) iglob, (mu(j,2,i), j = 1, 3)
        end do
      end if
      deallocate (buffermpimu)
      deallocate (reqrecdirsend)
      deallocate (reqrecdirrec)
      deallocate (reqsend)
      deallocate (reqrec)
      deallocate (req2send)
      deallocate (req2rec)
      deallocate (reqendsend)
      deallocate (reqendrec)
      deallocate (req2endsend)
      deallocate (req2endrec)
      if (rank.le.ndir-1) then
        deallocate (buffermpi1)
        deallocate (res)
        deallocate (zr)
        deallocate (diag)
        deallocate (dipfield)
        deallocate (h)
        deallocate (pp)
      else
        deallocate (buffermpi2)
        deallocate (dipfieldbis)
      end if
      return
      end
c
      subroutine inducejac_pme(matvec,nrhs,dodiis,ef,mu,murec)
      use atmlst
      use domdec
      use ewald
      use iounit
      use math
      use mpole
      use polar
      use polpot
      use timestat
      use mpi
      implicit none
c
c     solves the polarizable dipoles linear equations by jacobi
c     iterations coupled to the DIIS extrapolation.
c
      integer nrhs, info
      real*8  ef(3,nrhs,*), mu(3,nrhs,*), murec(3,nrhs,*)
      real*8, allocatable :: munew(:,:,:), h(:,:,:)
      real*8, allocatable :: xdiis(:,:), ediis(:,:), bmat(:,:),
     $   bloc(:,:), cex(:)
      integer i, j, k, iipole, it, ind, ndismx, nmat, lenb
      logical dodiis
      parameter (ndismx=25)
      integer ipiv(ndismx+1)
      real*8  zero, one, rnorm(2), rr, xx(1)
      real*8 term
      real*8 time0,time1,time2,time3
      save    zero, one, xx
      data    zero/0.0d0/, one/1.0d0/, xx/0.0d0/
      external matvec
      real*8, allocatable :: dipfield(:,:,:),dipfieldbis(:,:,:)
c
c     MPI
c
      real*8, allocatable :: buffermpi1(:,:,:),buffermpi2(:,:,:)
      real*8, allocatable :: buffermpimu(:,:,:)
      integer ierr, tag, proc
      integer reqnorm,reqdiis(2*ndismx+1)
      integer,allocatable :: reqrecdirrec(:),reqrecdirsend(:)
      integer,allocatable :: reqrec(:),reqsend(:)
      integer,allocatable :: req2rec(:),req2send(:)
      integer status(MPI_STATUS_SIZE)
c
 1000 format(' itsolv converged after ',I3,' iterations.',/,
     $       ' final residual norm = ',3D14.7)
 1010 format(' residual norm at iteration ',I3,':',3D12.2)
 1020 format(' Jacobi/DIIS solver: induced dipoles',/,
     $  ' ipole       mux         muy         muz')
 1021 format(' Jacobi/DIIS solver: induced p-dipoles',/,
     $  ' ipole       mux         muy         muz')
 1030 format(i6,2x,f10.7,2x,f10.7,2x,f10.7)
c
c
      if (rank.le.ndir-1) then
        allocate (buffermpi1(3,nrhs,max(npoleloc,1)))
        buffermpi1 = 0d0
        allocate (buffermpimu(3,nrhs,max(npoleloc,1)))
        buffermpimu = 0.0d0
        allocate (munew(3,nrhs,max(1,npolebloc)))
        munew = 0.0d0
        allocate (dipfield(3,nrhs,max(1,npoleloc)))
        dipfield = 0d0
        allocate (h(3,nrhs,max(1,npolebloc)))
        h = 0.0d0
        if (dodiis) then
          nmat = 1
          lenb = ndismx + 1
          allocate (xdiis(3*nrhs*max(1,npoleloc),ndismx))
          allocate (ediis(3*nrhs*max(1,npoleloc),ndismx))
          allocate (bmat(lenb,lenb))
          allocate (bloc(lenb,lenb))
          allocate (cex(lenb))
          bmat = 0.0d0
        end if
      else
        allocate (buffermpi2(3,nrhs,max(npolerecloc,1)))
        buffermpi2 = 0d0
        allocate (buffermpimu(3,nrhs,max(1,npolerecloc)))
        buffermpimu = 0.0d0
        allocate (dipfieldbis(3,nrhs,max(1,npolerecloc)))
        dipfieldbis = 0d0
      end if
      allocate (reqrecdirsend(nproc))
      allocate (reqrecdirrec(nproc))
      allocate (reqrec(nproc))
      allocate (reqsend(nproc))
      allocate (req2rec(nproc))
      allocate (req2send(nproc))
c
c     main loop:
c
      do it = 1, politer
        rnorm = 0.0d0
c
c     MPI : begin reception
c
        if (rank.le.ndir-1) then
          do i = 1, n_recep1
            tag = nproc*rank + p_recep1(i) + 1
            call MPI_IRECV(mu(1,1,bufbegpole(p_recep1(i)+1)),
     $       3*nrhs*domlen(p_recep1(i)+1),MPI_REAL8,p_recep1(i),tag,
     $       COMM_BEAD,reqrec(i),ierr)
          end do
        else
          do i = 1, nrecdir_recep1
            proc = precdir_recep1(i)
            tag = nproc*rank + proc + 1
            call MPI_IRECV(buffermpimu(1,1,bufbeg2(proc+1)),
     $       3*nrhs*buflen2(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $       req2rec(i),ierr)
          end do
        end if
c
c      Begin the reception of the reciprocal fields
c
        if (rank.le.ndir-1) then
          do i = 1, nrecdir_send1
            proc = precdir_send1(i)
            tag = nproc*rank + proc + 1
            call MPI_IRECV(buffermpi1(1,1,bufbeg1(proc+1)),
     $       3*nrhs*buflen1(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $       reqrecdirrec(i),ierr)
          end do
c
c     The PME processes compute the reciprocal matrix vector product
c
        else
          time0 = mpi_wtime()
          call tmatxbrecip(murec,nrhs,dipfieldbis)
          time1 = mpi_wtime()
          if (it.eq.1) timerecdip = timerecdip + time1-time0
          do i = 1, nrecdir_recep1
            proc = precdir_recep1(i)
            tag = nproc*proc + rank + 1
            do j = 0, buflen2(proc+1)-1
              call amove(3*nrhs,dipfieldbis(1,1,polerecloc(
     $          buf2(bufbeg2(proc+1)+j))),
     $          buffermpi2(1,1,bufbeg2(proc+1)+j))
            end do
            call MPI_ISEND(buffermpi2(1,1,bufbeg2(proc+1)),
     $      3*nrhs*buflen2(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $      reqrecdirsend(i),ierr)
          end do
          do i = 1, nrecdir_recep1
            call MPI_WAIT(reqrecdirsend(i),status,ierr)
          end do
        end if
c
        if (rank.le.ndir-1) then
c
c     jacobi step:
c
c    The real space processes extract the recip fields, compute the real fields
c    and add them
c
         term = (4.0d0/3.0d0) * aewald**3 / sqrtpi
         time0 = mpi_wtime()
         call matvec(nrhs,.false.,mu,h)
         time1 = mpi_wtime()
         if (it.eq.1) timerealdip = timerealdip + time1-time0
         call commfield(nrhs,h)
c
          do i = 1, nrecdir_send1
            proc = precdir_send1(i)
            call MPI_WAIT(reqrecdirrec(i),status,ierr)
            do j = 0, buflen1(proc+1)-1
              call amove(3*nrhs,buffermpi1(1,1,bufbeg1(proc+1)+j),
     $          dipfield(1,1,poleloc(buf1(bufbeg1(proc+1)+j))))
            end do
          end do
c
          h(1:3,1:nrhs,1:npoleloc) = h(:,:,1:npoleloc)+
     $      dipfield(:,:,1:npoleloc)
     $     - term*mu(:,:,1:npoleloc)
c
          do i = 1, npoleloc
            iipole = poleglob(i)
            do k = 1, nrhs
              do j = 1, 3
                munew(j,k,i) = polarity(iipole)*(ef(j,k,i) - h(j,k,i))
              end do
            end do
          end do
c
          do k = 1, nrhs
            rnorm(k)=sum((munew(1:3,k,1:npoleloc)-
     $        mu(1:3,k,1:npoleloc))**2)
          end do
c
        end if
        call MPI_IALLREDUCE(MPI_IN_PLACE,rnorm(1),nrhs,MPI_REAL8,
     $    MPI_SUM,COMM_BEAD,reqnorm,ierr)
        if (rank.le.ndir-1) then
          if (dodiis) then
            ind = 0
            do i = 1, npoleloc
              do k = 1, nrhs
                do j = 1, 3
                  ind = ind + 1
                  xdiis(ind,nmat) = munew(j,k,i)
                  ediis(ind,nmat) = munew(j,k,i) - mu(j,k,i)
                end do
              end do
            end do
c
c           Compute Pulay's Matrix and extrapolate
c
            call diis(ndismx,3*nrhs*npoleloc,xdiis,ediis,
     $        bmat,nmat,reqdiis,comm_dir)
            do i = 1, 2*nmat-3
              call MPI_WAIT(reqdiis(i),status,ierr)
            end do
            bloc = bmat
            cex = 0.0d0
            cex(1) = one
            call dgesv(nmat,1,bloc,ndismx+1,ipiv,cex,nmat,info)
            munew = 0.0d0
            call extrap(3*nrhs*npoleloc,nmat-1,xdiis,cex,munew)
          end if
        time2 = mpi_wtime()
c
c     MPI : begin sending to other direct processes
c
          do i = 1, n_send1
            tag = nproc*p_send1(i) + rank + 1
            call MPI_ISEND(munew,3*nrhs*npoleloc,MPI_REAL8,p_send1(i),
     $       tag,COMM_BEAD,reqsend(i),ierr)
          end do
c
c     MPI : begin sending to PME processes
c
          do i = 1, nrecdir_send1
            proc = precdir_send1(i)
            tag = nproc*proc + rank + 1
            do j = 0, buflen1(proc+1)-1
              call amove(3*nrhs,munew(1,1,poleloc(
     $          buf1(bufbeg1(proc+1)+j))),
     $          buffermpimu(1,1,bufbeg1(proc+1)+j))
            end do
            call MPI_ISEND(buffermpimu(1,1,bufbeg1(proc+1)),3*nrhs*
     $      buflen1(proc+1),MPI_REAL8,proc,tag,COMM_BEAD,
     $      req2send(i),ierr)
          end do
c
          time0 = mpi_wtime()
          do i = 1, n_recep1
            call MPI_WAIT(reqrec(i),status,ierr)
          end do
          do i = 1, n_send1
            call MPI_WAIT(reqsend(i),status,ierr)
          end do
c
          do i = 1, nrecdir_send1
            call MPI_WAIT(req2send(i),status,ierr)
          end do
          mu(:,:,1:npoleloc) = munew(:,:,1:npoleloc)
        else
           do i = 1, nrecdir_recep1
             proc = precdir_recep1(i)
            call MPI_WAIT(req2rec(i),status,ierr)
            do j = 0, buflen2(proc+1)-1
              call amove(3*nrhs,buffermpimu(1,1,bufbeg2(proc+1)+j),
     $          murec(1,1,polerecloc(buf2(bufbeg2(proc+1)+j))))
            end do
          end do
        end if
c
c     compute the norm of the increment.
c
        call MPI_WAIT(reqnorm,status,ierr)
        rr = zero
        do k = 1, nrhs
         rnorm(k) = sqrt(rnorm(k)/dble(3*npolar))
c          rnorm(k) = sqrt(rnorm(k))
          rr = max(rnorm(k),rr)
        end do
        if (polprt.ge.2.and.rank.eq.0)
     $         write(6,1010) it, (rnorm(k), k = 1, nrhs)
        if (rr.lt.poleps) then
          if (polprt.ge.1.and.rank.eq.0)
     $       write(6,1000) it, (rnorm(k), k = 1, nrhs)
          goto 10
        end if
      end do
 10   continue
c
      if (polprt.ge.3) then
        write(iout,1020)
        do i = 1, npoleloc
          iipole = poleglob(i)
          write(iout,1030) iipole, (mu(j,1,i), j = 1, 3)
        end do
      end if
      if (polprt.ge.4) then
        write(iout,1021)
        do i = 1, npoleloc
          iipole = poleglob(i)
          write(iout,1030) iipole, (mu(j,2,i), j = 1, 3)
        end do
      end if
c
c     free the memory.
c
      deallocate (reqsend)
      deallocate (reqrec)
      deallocate (req2send)
      deallocate (req2rec)
      deallocate (reqrecdirsend)
      deallocate (reqrecdirrec)
      deallocate (buffermpimu)
      if (rank.le.ndir-1) then
        deallocate (munew)
        deallocate (h)
        deallocate (dipfield)
        if (dodiis) then
          deallocate (xdiis)
          deallocate (ediis)
          deallocate (bmat)
          deallocate (bloc)
          deallocate (cex)
        end if
      else
        deallocate (dipfieldbis)
      end if
      return
      end
c
      subroutine efld0_direct(nrhs,ef)
c
c     Compute the direct space contribution to the permanent electric field.
c      Also compute the "p" field, which is used to
c     compute the energy according to the AMOEBA force field.
c
      use atmlst
      use atoms
      use couple
      use domdec
      use ewald
      use iounit
      use math
      use mpole
      use neigh
      use polar
      use polgrp
      use polpot
      use shunt
      implicit none
      integer i,iglob,kglob,nrhs,inl,ipoleloc
      real*8  ef(3,nrhs,npolebloc)
      integer ii, j, k, kkk, iipole, kkpole,kbis
      real*8  dx, dy, dz, d, d2, d3, d5, pdi, pti, ck,
     $  dkx, dky, dkz, dkr, qkxx, qkyy, qkzz, qkxy, qkxz, qkyz,
     $  qkx, qky, qkz, qkr
      real*8 dix, diy, diz, dir, qixx, qiyy, qizz, qixy, qixz, qiyz,
     $  qix, qiy, qiz, qir, ci
      real*8 damp, pgamma, expdamp, scale3, scale5, scale7
      real*8 drr3,drr5,drr7
      real*8 prr3,prr5,prr7
      real*8 dsc3,dsc5,dsc7
      real*8 psc3,psc5,psc7
      real*8 zero, pt6, one, f50
      real*8 ralpha, alsq2, alsq2n, bfac, exp2a
      real*8 bn(0:3), fim(3), fid(3), fip(3)
      real*8 fkd(3), fkp(3), fkm(3)
      real*8 erfc, cutoff2
      real*8, allocatable :: dscale(:)
      real*8, allocatable :: pscale(:)
      save   zero, pt6, one, f50
      data   zero/0.d0/, pt6/0.6d0/, one/1.d0/,f50/50.d0/
      character*6 mode
c
 1000 format(' Warning, system moved too much since last neighbor list
     $  update, try lowering nlupdate')
c
      mode = 'EWALD'
      call switch (mode)
      cutoff2 = cut2
c
      allocate (dscale(n))
      allocate (pscale(n))
      do i = 1, n
         dscale(i) = 1.0d0
         pscale(i) = 1.0d0
      end do
c
      do ii = 1, npolelocnl
        iipole = poleglobnl(ii)
c
c       skip atom if it is not polarizable
c
        if (polarity(iipole).eq.0.0d0) cycle
        iglob = ipole(iipole)
        i = loc(iglob)
        ipoleloc = poleloc(iipole)
        if (i.eq.0) then
          write(iout,1000)
          cycle
        end if
        pdi = pdamp(iipole)
        pti = thole(iipole)
        ci = rpole(1,iipole)
        dix = rpole(2,iipole)
        diy = rpole(3,iipole)
        diz = rpole(4,iipole)
        qixx = rpole(5,iipole)
        qixy = rpole(6,iipole)
        qixz = rpole(7,iipole)
        qiyy = rpole(9,iipole)
        qiyz = rpole(10,iipole)
        qizz = rpole(13,iipole)
        do j = 1, n12(iglob)
           pscale(i12(j,iglob)) = p2scale
        end do
        do j = 1, n13(iglob)
           pscale(i13(j,iglob)) = p3scale
        end do
        do j = 1, n14(iglob)
           pscale(i14(j,iglob)) = p4scale
           do k = 1, np11(iglob)
              if (i14(j,iglob) .eq. ip11(k,iglob))
     &           pscale(i14(j,iglob)) = p4scale * p41scale
           end do
        end do
        do j = 1, n15(iglob)
           pscale(i15(j,iglob)) = p5scale
        end do
        do j = 1, np11(iglob)
           dscale(ip11(j,iglob)) = d1scale
        end do
        do j = 1, np12(iglob)
           dscale(ip12(j,iglob)) = d2scale
        end do
        do j = 1, np13(iglob)
           dscale(ip13(j,iglob)) = d3scale
        end do
        do j = 1, np14(iglob)
           dscale(ip14(j,iglob)) = d4scale
        end do
c
        do kkk = 1, nelst(ii)
          kkpole = elst(kkk,ii)
          kbis = poleloc(kkpole)
          kglob = ipole(kkpole)
          if (kbis.eq.0) then
            write(iout,1000)
            cycle
          end if
          dx = x(kglob) - x(iglob)
          dy = y(kglob) - y(iglob)
          dz = z(kglob) - z(iglob)
          call image(dx,dy,dz)
          d2 = dx*dx + dy*dy + dz*dz
          if (d2.le.cutoff2) then
            d  = sqrt(d2)
c
c     calculate the error function damping terms
c
            ralpha = aewald * d
            bn(0) = erfc(ralpha) / d
            alsq2 = 2.0d0 * aewald**2
            alsq2n = 0.0d0
            if (aewald .gt. 0.0d0)
     &        alsq2n = 1.0d0 / (sqrtpi*aewald)
            exp2a = exp(-ralpha**2)
            do j = 1, 3
              bfac = dble(j+j-1)
              alsq2n = alsq2 * alsq2n
              bn(j) = (bfac*bn(j-1)+alsq2n*exp2a) / d2
            end do
c
            d3   = d*d2
            d5   = d3*d2
            ck   = rpole(1,kkpole)
            dkx  = rpole(2,kkpole)
            dky  = rpole(3,kkpole)
            dkz  = rpole(4,kkpole)
            qkxx = rpole(5,kkpole)
            qkxy = rpole(6,kkpole)
            qkxz = rpole(7,kkpole)
            qkyy = rpole(9,kkpole)
            qkyz = rpole(10,kkpole)
            qkzz = rpole(13,kkpole)
            damp = pdi*pdamp(kkpole)
            scale3 = one
            scale5 = one
            scale7 = one
            if (damp.ne.zero) then
              pgamma = min(pti,thole(kkpole))
              damp = -pgamma*(d/damp)**3
              if (damp.gt.-F50) then
                expdamp = exp(damp)
                scale3 = one - expdamp
                scale5 = one - expdamp*(one-damp)
                scale7 = one - expdamp
     &                      *(one-damp + pt6*damp**2)
              end if
            end if
            dsc3 = scale3 * dscale(kglob)
            dsc5 = scale5 * dscale(kglob)
            dsc7 = scale7 * dscale(kglob)
            psc3 = scale3 * pscale(kglob)
            psc5 = scale5 * pscale(kglob)
            psc7 = scale7 * pscale(kglob)
            drr3 = (1.0d0-dsc3) / (d*d2)
            drr5 = 3.0d0 * (1.0d0-dsc5) / (d*d2*d2)
            drr7 = 15.0d0 * (1.0d0-dsc7) / (d*d2*d2*d2)
            prr3 = (1.0d0-psc3) / (d*d2)
            prr5 = 3.0d0 * (1.0d0-psc5) / (d*d2*d2)
            prr7 = 15.0d0 * (1.0d0-psc7) / (d*d2*d2*d2)
c
c     compute some intermediate quantities
c
            dir = dix*dx + diy*dy + diz*dz
            qix = qixx*dx + qixy*dy + qixz*dz
            qiy = qixy*dx + qiyy*dy + qiyz*dz
            qiz = qixz*dx + qiyz*dy + qizz*dz
            qir = qix*dx + qiy*dy + qiz*dz
            dkr = dkx*dx + dky*dy + dkz*dz
            qkx = qkxx*dx + qkxy*dy + qkxz*dz
            qky = qkxy*dx + qkyy*dy + qkyz*dz
            qkz = qkxz*dx + qkyz*dy + qkzz*dz
            qkr = qkx*dx + qky*dy + qkz*dz
c
            fim(1) = -dx*(bn(1)*ck-bn(2)*dkr+bn(3)*qkr)
     &                   - bn(1)*dkx + 2.0d0*bn(2)*qkx
            fim(2) = -dy*(bn(1)*ck-bn(2)*dkr+bn(3)*qkr)
     &                   - bn(1)*dky + 2.0d0*bn(2)*qky
            fim(3) = -dz*(bn(1)*ck-bn(2)*dkr+bn(3)*qkr)
     &                   - bn(1)*dkz + 2.0d0*bn(2)*qkz
            fkm(1) = dx*(bn(1)*ci+bn(2)*dir+bn(3)*qir)
     &                  - bn(1)*dix - 2.0d0*bn(2)*qix
            fkm(2) = dy*(bn(1)*ci+bn(2)*dir+bn(3)*qir)
     &                  - bn(1)*diy - 2.0d0*bn(2)*qiy
            fkm(3) = dz*(bn(1)*ci+bn(2)*dir+bn(3)*qir)
     &                  - bn(1)*diz - 2.0d0*bn(2)*qiz
            fid(1) = -dx*(drr3*ck-drr5*dkr+drr7*qkr)
     &                   - drr3*dkx + 2.0d0*drr5*qkx
            fid(2) = -dy*(drr3*ck-drr5*dkr+drr7*qkr)
     &                  - drr3*dky + 2.0d0*drr5*qky
            fid(3) = -dz*(drr3*ck-drr5*dkr+drr7*qkr)
     &                   - drr3*dkz + 2.0d0*drr5*qkz
            fkd(1) = dx*(drr3*ci+drr5*dir+drr7*qir)
     &                  - drr3*dix - 2.0d0*drr5*qix
            fkd(2) = dy*(drr3*ci+drr5*dir+drr7*qir)
     &                  - drr3*diy - 2.0d0*drr5*qiy
            fkd(3) = dz*(drr3*ci+drr5*dir+drr7*qir)
     &                     - drr3*diz - 2.0d0*drr5*qiz
            fip(1) = -dx*(prr3*ck-prr5*dkr+prr7*qkr)
     &                   - prr3*dkx + 2.0d0*prr5*qkx
            fip(2) = -dy*(prr3*ck-prr5*dkr+prr7*qkr)
     &                   - prr3*dky + 2.0d0*prr5*qky
            fip(3) = -dz*(prr3*ck-prr5*dkr+prr7*qkr)
     &                   - prr3*dkz + 2.0d0*prr5*qkz
            fkp(1) = dx*(prr3*ci+prr5*dir+prr7*qir)
     &                  - prr3*dix - 2.0d0*prr5*qix
            fkp(2) = dy*(prr3*ci+prr5*dir+prr7*qir)
     &                  - prr3*diy - 2.0d0*prr5*qiy
            fkp(3) = dz*(prr3*ci+prr5*dir+prr7*qir)
     &                  - prr3*diz - 2.0d0*prr5*qiz
            ef(1,1,ipoleloc) = ef(1,1,ipoleloc) + fim(1) - fid(1)
            ef(2,1,ipoleloc) = ef(2,1,ipoleloc) + fim(2) - fid(2)
            ef(3,1,ipoleloc) = ef(3,1,ipoleloc) + fim(3) - fid(3)
            ef(1,2,ipoleloc) = ef(1,2,ipoleloc) + fim(1) - fip(1)
            ef(2,2,ipoleloc) = ef(2,2,ipoleloc) + fim(2) - fip(2)
            ef(3,2,ipoleloc) = ef(3,2,ipoleloc) + fim(3) - fip(3)
c
            ef(1,1,kbis) = ef(1,1,kbis) + fkm(1) - fkd(1)
            ef(2,1,kbis) = ef(2,1,kbis) + fkm(2) - fkd(2)
            ef(3,1,kbis) = ef(3,1,kbis) + fkm(3) - fkd(3)
            ef(1,2,kbis) = ef(1,2,kbis) + fkm(1) - fkp(1)
            ef(2,2,kbis) = ef(2,2,kbis) + fkm(2) - fkp(2)
            ef(3,2,kbis) = ef(3,2,kbis) + fkm(3) - fkp(3)
          end if
        end do
        do j = 1, n12(iglob)
           pscale(i12(j,iglob)) = 1.0d0
        end do
        do j = 1, n13(iglob)
           pscale(i13(j,iglob)) = 1.0d0
        end do
        do j = 1, n14(iglob)
           pscale(i14(j,iglob)) = 1.0d0
        end do
        do j = 1, n15(iglob)
           pscale(i15(j,iglob)) = 1.0d0
        end do
        do j = 1, np11(iglob)
           dscale(ip11(j,iglob)) = 1.0d0
        end do
        do j = 1, np12(iglob)
           dscale(ip12(j,iglob)) = 1.0d0
        end do
        do j = 1, np13(iglob)
           dscale(ip13(j,iglob)) = 1.0d0
        end do
        do j = 1, np14(iglob)
           dscale(ip14(j,iglob)) = 1.0d0
        end do
      end do
c
      deallocate (dscale)
      deallocate (pscale)
c
      return
      end
c
      subroutine tmatxb_pme(nrhs,dodiag,mu,efi)
c
c     Compute the direct space contribution to the electric field due to the current value
c     of the induced dipoles
c
      use sizes
      use atoms
      use atmlst
      use domdec
      use ewald
      use group
      use math
      use mpole
      use neigh
      use polar
      use polgrp
      use polpot
      use shunt
      implicit none
      integer i,nrhs,iglob,kglob,kbis,iipole,kkpole,kkpoleloc
      integer ipoleloc
      real*8  mu(3,nrhs,*), efi(3,nrhs,npolebloc)
      logical dodiag
      integer j, ii, kkk, irhs, inl
      real*8  dx, dy, dz, d, d2, damp, expdamp, pgamma,
     $  scale3, scale5, pdi, pti 
      real*8 ralpha, alsq2, alsq2n, bfac, exp2a
      real*8 rr3, rr5, dukx, duky, dukz, pukx, puky, pukz, puir, pukr,
     $  duir, dukr
      real*8 duix, duiy, duiz, puix, puiy, puiz
      real*8 bn(0:3), fid(3), fip(3), fimd(3), fimp(3)
      real*8 fkd(3), fkp(3), fkmd(3), fkmp(3)
      real*8  zero, one, f50
      real*8, allocatable :: dscale(:)
      real*8  erfc, cutoff2
      save    zero, one, f50
      data    zero/0.d0/, one/1.d0/, f50/50.d0/
      character*6 mode
      external erfc
c
c     initialize the result vector
c
      do i = 1, npolebloc
        do irhs = 1, nrhs
          do j = 1, 3
            efi(j,irhs,i) = zero
          end do
        end do
      end do
      allocate (dscale(n))
      do i = 1, n
         dscale(i) = 1.0d0
      end do
c
c     gather some parameters, then set up the damping factors.
c
      mode = 'EWALD'
      call switch (mode)
      cutoff2 = cut2
c
      do ii = 1, npolelocnl
        iipole = poleglobnl(ii)
        iglob = ipole(iipole)
        i = loc(iglob)
        ipoleloc = poleloc(iipole)
        if (i.eq.0) cycle
        pdi = pdamp(iipole)
        pti = thole(iipole)
        duix = mu(1,1,ipoleloc)
        duiy = mu(2,1,ipoleloc)
        duiz = mu(3,1,ipoleloc)
        puix = mu(1,2,ipoleloc)
        puiy = mu(2,2,ipoleloc)
        puiz = mu(3,2,ipoleloc)
        do j = 1, np11(iglob)
           dscale(ip11(j,iglob)) = u1scale
        end do
        do j = 1, np12(iglob)
           dscale(ip12(j,iglob)) = u2scale
        end do
        do j = 1, np13(iglob)
           dscale(ip13(j,iglob)) = u3scale
        end do
        do j = 1, np14(iglob)
           dscale(ip14(j,iglob)) = u4scale
        end do
c
        do kkk = 1,nelst(ii)
          kkpole = elst(kkk,ii)
          kglob = ipole(kkpole)
          kkpoleloc = poleloc(kkpole)
          if (kkpoleloc.eq.0) cycle
          dx = x(kglob) - x(iglob)
          dy = y(kglob) - y(iglob)
          dz = z(kglob) - z(iglob)
          call image(dx,dy,dz)
          d2 = dx*dx + dy*dy + dz*dz
          if (d2.le.cutoff2) then
c
c     compute the distances and the scaling factors according to
c     Thole's model.
c
            d  = sqrt(d2)
            dukx = mu(1,1,kkpoleloc)
            duky = mu(2,1,kkpoleloc)
            dukz = mu(3,1,kkpoleloc)
            pukx = mu(1,2,kkpoleloc)
            puky = mu(2,2,kkpoleloc)
            pukz = mu(3,2,kkpoleloc)
c
            ralpha = aewald * d
            bn(0) = erfc(ralpha) / d
            alsq2 = 2.0d0 * aewald**2
            alsq2n = 0.0d0
            if (aewald .gt. 0.0d0)
     &        alsq2n = 1.0d0 / (sqrtpi*aewald)
            exp2a = exp(-ralpha**2)
            do j = 1, 2
              bfac = dble(j+j-1)
              alsq2n = alsq2 * alsq2n
              bn(j) = (bfac*bn(j-1)+alsq2n*exp2a) / d2
            end do
c
            scale3 = dscale(kglob)
            scale5 = dscale(kglob)
            damp = pdi*pdamp(kkpole)
            if (damp.ne.zero) then
              pgamma = min(pti,thole(kkpole))
              damp = -pgamma*(d/damp)**3
              if (damp .gt. -f50) then
                expdamp = exp(damp)
                scale3 = scale3 * (one - expdamp)
                scale5 = scale5 * (one - expdamp*(one - damp))
              end if
            end if
c
c     compute the field.
c
            rr3 = (1.0d0-scale3) / (d*d2)
            rr5 = 3.0d0 * (1.0d0-scale5) / (d*d2*d2)
            duir = dx*duix + dy*duiy + dz*duiz
            dukr = dx*dukx + dy*duky + dz*dukz
            puir = dx*puix + dy*puiy + dz*puiz
            pukr = dx*pukx + dy*puky + dz*pukz
            fimd(1) = -bn(1)*dukx + bn(2)*dukr*dx
            fimd(2) = -bn(1)*duky + bn(2)*dukr*dy
            fimd(3) = -bn(1)*dukz + bn(2)*dukr*dz
            fkmd(1) = -bn(1)*duix + bn(2)*duir*dx
            fkmd(2) = -bn(1)*duiy + bn(2)*duir*dy
            fkmd(3) = -bn(1)*duiz + bn(2)*duir*dz
            fimp(1) = -bn(1)*pukx + bn(2)*pukr*dx
            fimp(2) = -bn(1)*puky + bn(2)*pukr*dy
            fimp(3) = -bn(1)*pukz + bn(2)*pukr*dz
            fkmp(1) = -bn(1)*puix + bn(2)*puir*dx
            fkmp(2) = -bn(1)*puiy + bn(2)*puir*dy
            fkmp(3) = -bn(1)*puiz + bn(2)*puir*dz
            fid(1) = -rr3*dukx + rr5*dukr*dx
            fid(2) = -rr3*duky + rr5*dukr*dy
            fid(3) = -rr3*dukz + rr5*dukr*dz
            fkd(1) = -rr3*duix + rr5*duir*dx
            fkd(2) = -rr3*duiy + rr5*duir*dy
            fkd(3) = -rr3*duiz + rr5*duir*dz
            fip(1) = -rr3*pukx + rr5*pukr*dx
            fip(2) = -rr3*puky + rr5*pukr*dy
            fip(3) = -rr3*pukz + rr5*pukr*dz
            fkp(1) = -rr3*puix + rr5*puir*dx
            fkp(2) = -rr3*puiy + rr5*puir*dy
            fkp(3) = -rr3*puiz + rr5*puir*dz
            efi(1,1,ipoleloc) = efi(1,1,ipoleloc) - fimd(1) + fid(1)
            efi(2,1,ipoleloc) = efi(2,1,ipoleloc) - fimd(2) + fid(2)
            efi(3,1,ipoleloc) = efi(3,1,ipoleloc) - fimd(3) + fid(3)
            efi(1,2,ipoleloc) = efi(1,2,ipoleloc) - fimp(1) + fip(1)
            efi(2,2,ipoleloc) = efi(2,2,ipoleloc) - fimp(2) + fip(2)
            efi(3,2,ipoleloc) = efi(3,2,ipoleloc) - fimp(3) + fip(3)
c
            efi(1,1,kkpoleloc) = efi(1,1,kkpoleloc) - fkmd(1) + fkd(1)
            efi(2,1,kkpoleloc) = efi(2,1,kkpoleloc) - fkmd(2) + fkd(2)
            efi(3,1,kkpoleloc) = efi(3,1,kkpoleloc) - fkmd(3) + fkd(3)
            efi(1,2,kkpoleloc) = efi(1,2,kkpoleloc) - fkmp(1) + fkp(1)
            efi(2,2,kkpoleloc) = efi(2,2,kkpoleloc) - fkmp(2) + fkp(2)
            efi(3,2,kkpoleloc) = efi(3,2,kkpoleloc) - fkmp(3) + fkp(3)
          end if
        end do
c
c     reset interaction scaling coefficients for connected atoms
c
        do j = 1, np11(iglob)
           dscale(ip11(j,iglob)) = 1.0d0
        end do
        do j = 1, np12(iglob)
           dscale(ip12(j,iglob)) = 1.0d0
        end do
        do j = 1, np13(iglob)
           dscale(ip13(j,iglob)) = 1.0d0
        end do
        do j = 1, np14(iglob)
           dscale(ip14(j,iglob)) = 1.0d0
        end do
      end do
      if(dodiag) then
c
c     if dodiag is true, also compute the "self-induced" field,
c     i.e., the diagonal portion of the matrix/vector product.
c
        do i = 1, npoleloc
          iipole = poleglob(i)
          do irhs = 1, nrhs
            do j = 1, 3
              efi(j,irhs,i) = efi(j,irhs,i) +
     $           mu(j,irhs,i)/polarity(iipole)
            end do
          end do
        end do
      end if
c
c     perform deallocation of some local arrays
c
      deallocate (dscale)
      return
      end
c
      subroutine efld0_recip
c
c     Compute the reciprocal space contribution to the electric field due to the permanent 
c     multipoles
c
      use atmlst
      use bound
      use boxes
      use domdec
      use ewald
      use fft
      use math
      use mpole
      use pme
      use timestat
      use mpi
      implicit none
      integer ierr
      integer status(MPI_STATUS_SIZE),tag
      integer i,j,k,iglob,iipole
      integer k1,k2,k3
      integer m1,m2,m3
      integer nf1,nf2,nf3
      real*8 r1,r2,r3
      real*8 h1,h2,h3
      real*8 volterm,denom
      real*8 hsq,expterm
      real*8 term,pterm
      real*8 cmp(10),fmp(10)
      real*8, allocatable :: qgridmpi(:,:,:,:,:)
      integer, allocatable :: reqrec(:),reqsend(:)
      integer, allocatable :: reqbcastrec(:),reqbcastsend(:)
      real*8 time0,time1
c
      allocate (reqrec(nrec))
      allocate (reqsend(nrec))
      allocate (reqbcastrec(nrec))
      allocate (reqbcastsend(nrec))
      allocate (qgridmpi(2,n1mpimax,n2mpimax,n3mpimax,nrec_recep))
c
c     MPI : Begin reception
c
      do i = 1, nrec_recep
        tag = nrec*rank_bis + prec_recep(i) + 1
        call MPI_IRECV(qgridmpi(1,1,1,1,i),2*n1mpimax*n2mpimax*
     $   n3mpimax,MPI_REAL8,prec_recep(i),tag,
     $   comm_rec,reqrec(i),ierr)
      end do
c
c     return if the Ewald coefficient is zero
c
      if (aewald .lt. 1.0d-6)  return
c
c     zero out the PME charge grid
      qgridin_2d = 0d0
c
c     fill the pme grid, loop over the multipoles sites
c
      time0 = mpi_wtime()
      do i = 1, npolerecloc
         iipole = polerecglob(i)
         iglob = ipole(iipole)
         cmp(1) = rpole(1,iipole)
         cmp(2) = rpole(2,iipole)
         cmp(3) = rpole(3,iipole)
         cmp(4) = rpole(4,iipole)
         cmp(5) = rpole(5,iipole)
         cmp(6) = rpole(9,iipole)
         cmp(7) = rpole(13,iipole)
         cmp(8) = 2.0d0 * rpole(6,iipole)
         cmp(9) = 2.0d0 * rpole(7,iipole)
         cmp(10) = 2.0d0 * rpole(10,iipole)
c
c     compute B-spline coefficients
c
         call bspline_fill_site(iglob,i)
c
c     convert Cartesian multipoles to fractional coordinates
c
        call cmp_to_fmp_site(cmp,fmp)
c
c     assign PME grid
c
        call grid_mpole_site(iglob,i,fmp)
      end do
      time1 = mpi_wtime()
      timegrid1 = timegrid1 + time1-time0
c
c     MPI : begin sending
c
      time0 = mpi_wtime()
      do i = 1, nrec_send
        tag = nrec*prec_send(i) + rank_bis + 1
        call MPI_ISEND(qgridin_2d(1,1,1,1,i+1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_REAL8,
     $   prec_send(i),tag,comm_rec,reqsend(i),ierr)
      end do
c
      do i = 1, nrec_recep
        call MPI_WAIT(reqrec(i),status,ierr)
      end do
      do i = 1, nrec_send
        call MPI_WAIT(reqsend(i),status,ierr)
      end do
c
c     do the reduction 'by hand'
c
      do i = 1, nrec_recep
        call aadd(2*n1mpimax*n2mpimax*n3mpimax,
     $   qgridin_2d(1,1,1,1,1),
     $   qgridmpi(1,1,1,1,i),qgridin_2d(1,1,1,1,1))
      end do
      time1 = mpi_wtime()
      timerecreccomm = timerecreccomm + time1 - time0
c
c     Perform 3-D FFT forward transform
c
      time0 = mpi_wtime()
      call fft2d_frontmpi(qgridin_2d,qgridout_2d,n1mpimax,n2mpimax,
     $ n3mpimax)
      time1 = mpi_wtime()
      timeffts = timeffts + time1-time0
c
c     make the scalar summation over reciprocal lattice
c
      time0 = mpi_wtime()
      if ((istart2(rank_bis+1).eq.1).and.(jstart2(rank_bis+1).eq.1).and.
     $   (kstart2(rank_bis+1).eq.1)) then
           qfac_2d(1,1,1) = 0.0d0
      end if
      pterm = (pi/aewald)**2
      volterm = pi * volbox
      nf1 = (nfft1+1) / 2
      nf2 = (nfft2+1) / 2
      nf3 = (nfft3+1) / 2
      do k3 = kstart2(rank_bis+1),kend2(rank_bis+1)
        do k2 = jstart2(rank_bis+1),jend2(rank_bis+1)
          do k1 = istart2(rank_bis+1),iend2(rank_bis+1)
            m1 = k1 - 1
            m2 = k2 - 1
            m3 = k3 - 1
            if (k1 .gt. nf1)  m1 = m1 - nfft1
            if (k2 .gt. nf2)  m2 = m2 - nfft2
            if (k3 .gt. nf3)  m3 = m3 - nfft3
            if ((m1.eq.0).and.(m2.eq.0).and.(m3.eq.0)) goto 10
            r1 = dble(m1)
            r2 = dble(m2)
            r3 = dble(m3)
            h1 = recip(1,1)*r1 + recip(1,2)*r2 + recip(1,3)*r3
            h2 = recip(2,1)*r1 + recip(2,2)*r2 + recip(2,3)*r3
            h3 = recip(3,1)*r1 + recip(3,2)*r2 + recip(3,3)*r3
            hsq = h1*h1 + h2*h2 + h3*h3
            term = -pterm * hsq
            expterm = 0.0d0
            if ((term .gt. -50.0d0)) then
               denom = volterm*hsq*bsmod1(k1)*bsmod2(k2)*bsmod3(k3)
               expterm = exp(term) / denom
               if (.not. use_bounds) then
                  expterm = expterm * (1.0d0-cos(pi*xbox*sqrt(hsq)))
               else if (octahedron) then
                  if (mod(m1+m2+m3,2) .ne. 0)  expterm = 0.0d0
               end if
            qfac_2d(k1-istart2(rank_bis+1)+1,k2-jstart2(rank_bis+1)+1,
     $        k3-kstart2(rank_bis+1)+1) = expterm
            end if
 10         continue
          end do
        end do
      end do
c
c     account for the zeroth grid point for a finite system
c
      if ((istart2(rank_bis+1).eq.1).and.(jstart2(rank_bis+1).eq.1).and.
     $   (kstart2(rank_bis+1).eq.1)) then
        if (.not. use_bounds) then
           expterm = 0.5d0 * pi / xbox
           qfac_2d(1,1,1) = expterm
        end if
      end if
c
c     complete the transformation of the charge grid
c
      do k = 1, ksize2(rank_bis+1)
         do j = 1, jsize2(rank_bis+1)
           do i = 1, isize2(rank_bis+1)
             term = qfac_2d(i,j,k)
             qgridout_2d(1,i,j,k) = term*qgridout_2d(1,i,j,k)
             qgridout_2d(2,i,j,k) = term*qgridout_2d(2,i,j,k)
           end do
         end do
      end do
      time1 = mpi_wtime()
      timescalar = timescalar + time1-time0
c
c     perform 3-D FFT backward transform
c
      time0 = mpi_wtime()
      call fft2d_backmpi(qgridin_2d,qgridout_2d,n1mpimax,n2mpimax,
     $ n3mpimax)
      time1 = mpi_wtime()
      timeffts = timeffts + time1-time0
c
c     MPI : Begin reception
c
      time0 = mpi_wtime()
      do i = 1, nrec_send
        tag = nrec*rank_bis + prec_send(i) + 1
        call MPI_IRECV(qgridin_2d(1,1,1,1,i+1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_REAL8,
     $   prec_send(i),tag,comm_rec,reqbcastrec(i),ierr)
      end do
c
c     MPI : begin sending
c
      do i = 1, nrec_recep
        tag = nrec*prec_recep(i) + rank_bis + 1
        call MPI_ISEND(qgridin_2d(1,1,1,1,1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_REAL8,
     $   prec_recep(i),tag,comm_rec,reqbcastsend(i),ierr)
      end do
c
      do i = 1, nrec_send
        call MPI_WAIT(reqbcastrec(i),status,ierr)
      end do
      do i = 1, nrec_recep
        call MPI_WAIT(reqbcastsend(i),status,ierr)
      end do
      time1 = mpi_wtime()
      timerecreccomm = timerecreccomm + time1-time0
c
c     get field
c
      time0 = mpi_wtime()
      do i = 1, npolerecloc
        iipole = polerecglob(i)
        iglob = ipole(iipole)
        call fphi_mpole_site(iglob,i)
        call fphi_to_cphi_site(fphirec(1,i),cphirec(1,i))
      end do
      time1 = mpi_wtime()
      timegrid2 = timegrid2 + time1-time0
c
      deallocate (qgridmpi)
      deallocate (reqrec)
      deallocate (reqsend)
      return
      end
c
c
      subroutine tmatxbrecip(murec,nrhs,dipfieldbis)
c
c     Compute the reciprocal space contribution to the electric field due to the current  
c     value of the induced dipoles
c
      use atmlst
      use boxes
      use domdec
      use ewald
      use fft
      use math
      use mpole
      use pme
      use mpi
      implicit none
      integer ierr,iglob
      integer status(MPI_STATUS_SIZE),tag
      integer nrhs,iipole
      integer i,j,k
      real*8 fuind(3),fuinp(3)
      real*8 term
      real*8 a(3,3)
      real*8 fdip_phi1(10), fdip_phi2(10), fdip_sum_phi(20)
      real*8 dipfieldbis(3,nrhs,*)
      real*8 murec(3,nrhs,*)
      real*8, allocatable :: qgridmpi(:,:,:,:,:)
      integer, allocatable :: reqbcastrec(:),reqbcastsend(:)
      integer, allocatable :: reqrec(:),reqsend(:)
c
      allocate (reqbcastrec(nrec))
      allocate (reqbcastsend(nrec))
      allocate (reqrec(nrec))
      allocate (reqsend(nrec))
      allocate (qgridmpi(2,n1mpimax,n2mpimax,n3mpimax,nrec_recep))
c
c     MPI : Begin reception
c
      do i = 1, nrec_recep
        tag = nrec*rank_bis + prec_recep(i) + 1
        call MPI_IRECV(qgridmpi(1,1,1,1,i),2*n1mpimax*n2mpimax*n3mpimax,
     $   MPI_REAL8,prec_recep(i),tag,
     $   comm_rec,reqrec(i),ierr)
      end do
c
c     return if the Ewald coefficient is zero
c
      if (aewald .lt. 1.0d-6)  return
c
c     zero out the PME charge grid
      qgrid2in_2d = 0d0
c
c     fill the pme grid, loop over the induced dipoles sites
c
      do j = 1, 3
        a(1,j) = dble(nfft1) * recip(j,1)
        a(2,j) = dble(nfft2) * recip(j,2)
        a(3,j) = dble(nfft3) * recip(j,3)
      end do
      do i = 1, npolerecloc
        iipole = polerecglob(i)
        iglob = ipole(iipole)
c
c       Convert cartesian dipoles to fractional coordinates
c
        do k = 1, 3
           fuind(k) = a(k,1)*murec(1,1,i) + a(k,2)*murec(2,1,i)
     &                     + a(k,3)*murec(3,1,i)
           fuinp(k) = a(k,1)*murec(1,2,i) + a(k,2)*murec(2,2,i)
     &                     + a(k,3)*murec(3,2,i)
        end do
c
c     assign PME grid
c
        call grid_uind_site(iglob,i,fuind,fuinp,qgrid2in_2d)
      end do
c
c     MPI : begin sending
c
      do i = 1, nrec_send
        tag = nrec*prec_send(i) + rank_bis + 1
        call MPI_ISEND(qgrid2in_2d(1,1,1,1,i+1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_REAL8,
     $   prec_send(i),tag,comm_rec,reqsend(i),ierr)
      end do
c
      do i = 1, nrec_recep
        call MPI_WAIT(reqrec(i),status,ierr)
      end do
      do i = 1, nrec_send
        call MPI_WAIT(reqsend(i),status,ierr)
      end do
c
c     do the reduction 'by hand'
c
      do i = 1, nrec_recep
        call aadd(2*n1mpimax*n2mpimax*n3mpimax,
     $   qgrid2in_2d(1,1,1,1,1),qgridmpi(1,1,1,1,i),
     $   qgrid2in_2d(1,1,1,1,1))
      end do
c
c     Perform 3-D FFT forward transform
c
      call fft2d_frontmpi(qgrid2in_2d,qgrid2out_2d,n1mpimax,n2mpimax,
     $ n3mpimax)
c
c     complete the transformation of the charge grid
c
      do k = 1, ksize2(rank_bis+1)
         do j = 1, jsize2(rank_bis+1)
           do i = 1, isize2(rank_bis+1)
             term = qfac_2d(i,j,k)
             qgrid2out_2d(1,i,j,k) = term*qgrid2out_2d(1,i,j,k)
             qgrid2out_2d(2,i,j,k) = term*qgrid2out_2d(2,i,j,k)
           end do
         end do
      end do
c
c     perform 3-D FFT backward transform
c
      call fft2d_backmpi(qgrid2in_2d,qgrid2out_2d,n1mpimax,n2mpimax,
     $ n3mpimax)
c
c     MPI : Begin reception
c
      do i = 1, nrec_send
        tag = nrec*rank_bis + prec_send(i) + 1
        call MPI_IRECV(qgrid2in_2d(1,1,1,1,i+1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_REAL8,
     $   prec_send(i),tag,comm_rec,reqbcastrec(i),ierr)
      end do
c
c     MPI : begin sending
c
      do i = 1, nrec_recep
        tag = nrec*prec_recep(i) + rank_bis + 1
        call MPI_ISEND(qgrid2in_2d,
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_REAL8,
     $   prec_recep(i),tag,comm_rec,reqbcastsend(i),ierr)
      end do
c
      do i = 1, nrec_send
        call MPI_WAIT(reqbcastrec(i),status,ierr)
      end do
      do i = 1, nrec_recep
        call MPI_WAIT(reqbcastsend(i),status,ierr)
      end do
c
c     get fields
c
      do i = 1, npolerecloc
        iipole = polerecglob(i)
        iglob = ipole(iipole)
        call fphi_uind_site(iglob,i,fdip_phi1,fdip_phi2,fdip_sum_phi)
c
c     convert the dipole fields from fractional to Cartesian
c
        do k = 1, 3
           dipfieldbis(k,1,i) = a(k,1)*fdip_phi1(2)
     &                         + a(k,2)*fdip_phi1(3)
     &                         + a(k,3)*fdip_phi1(4)
           dipfieldbis(k,2,i) = a(k,1)*fdip_phi2(2)
     &                         + a(k,2)*fdip_phi2(3)
     $                         + a(k,3)*fdip_phi2(4)
        end do
      end do
      deallocate (qgridmpi)
      deallocate (reqrec)
      deallocate (reqsend)
      deallocate (reqbcastsend)
      deallocate (reqbcastrec)
      return
      end
