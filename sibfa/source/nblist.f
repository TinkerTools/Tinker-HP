c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ###############################################################
c     ##                                                           ##
c     ##  subroutine nblist  --  maintain pairwise neighbor lists  ##
c     ##                                                           ##
c     ###############################################################
c
c
c     "nblist" constructs and maintains nonbonded pair neighbor lists
c     for vdw and electrostatic interactions
c
c
      subroutine nblist(istep)
      use sizes
      use bond
      use chargetransfer
      use domdec
      use cutoff
      use neigh
      use potent
      use timestat
      use mpi
      implicit none
      integer istep,modnl
      real*8  time0,time1
c
c
c     check number of steps between nl updates
c
      modnl = mod(istep,ineigup)
      if (modnl.ne.0) return
      if ((use_clist).or.(use_mlist)) then
        if (allocated(nelst)) deallocate (nelst)
        allocate (nelst(nlocnl))
        if (allocated(elst)) deallocate (elst)
        allocate (elst(maxelst,nlocnl))
      end if
      nelst = 0
      elst = 0
      if (use_vlist) then
         if (allocated(nvlst)) deallocate (nvlst)
         allocate (nvlst(nlocnl))
         if (allocated(vlst)) deallocate (vlst)
         allocate (vlst(maxvlst,nlocnl))
         nvlst = 0
         vlst = 0
      end if
c
c     Bond-Bond 
c
      if (use_repulsion) then 
        if (allocated(nbondlst)) deallocate (nbondlst)
        allocate (nbondlst(nbondlocnl))
        if (allocated(bondlst)) deallocate (bondlst)
        allocate (bondlst(maxbondlst,nbondlocnl))
        nbondlst = 0
        bondlst = 0
c
c       Bond-lp
c
c        call rotlp
        if (allocated(nbondlplst)) deallocate (nbondlplst)
        allocate (nbondlplst(nbondlocnl))
        if (allocated(bondlplst)) deallocate (bondlplst)
        allocate (bondlplst(maxbondlst,nbondlocnl))
        nbondlplst = 0
        bondlplst = 0 
      end if
c
c     lp-lp
c
      if ((use_ctransfer).or.(use_dispersion).or.(use_repulsion)) then
        if (allocated(nlplplst)) deallocate (nlplplst)
        allocate (nlplplst(nlplocnl))
        if (allocated(lplplst)) deallocate (lplplst)
        allocate (lplplst(maxlplst,nlplocnl))
        nlplplst = 0
        lplplst = 0
      end if
c
c     atom-atom
c
      if (use_dispersion) then
        if (allocated(natatlst)) deallocate (natatlst)
        allocate (natatlst(nlocnl))
        if (allocated(atatlst)) deallocate (atatlst)
        allocate (atatlst(maxatlst,nlocnl))
        natatlst = 0
        atatlst = 0
      end if
c
c     lp-atom
c
      if (use_dispersion) then
        if (allocated(nlpatlst)) deallocate (nlpatlst)
        allocate (nlpatlst(nlocnl))
        if (allocated(lpatlst)) deallocate (lpatlst)
        allocate (lpatlst(maxatlst,nlocnl))
        nlpatlst = 0
        lpatlst = 0
      end if
c
c     lp-acceptor
c
      if (use_ctransfer) then
        if (allocated(nlpacclst)) deallocate (nlpacclst)
        allocate (nlpacclst(8*nlocnl))
        if (allocated(lpacclst)) deallocate (lpacclst)
        allocate (lpacclst(maxlplst,8*nlocnl))
        nlpacclst = 0
        lpacclst = 0
      end if
c
c     neighbor list to compute charge transfer electrostatic potential
c
      if ((use_ctransfer).and.(use_ctpot)) then
        if (allocated(nlpacclst)) deallocate (nlpacclst)
        allocate (nlpacclst(8*nlocnl))
        if (allocated(lpacclst)) deallocate (lpacclst)
        allocate (lpacclst(maxlplst,8*nlocnl))
        nlpacclst = 0
        lpacclst = 0
        if (allocated(naccpotlst)) deallocate (naccpotlst)
        allocate (naccpotlst(2,nacceptlocnl))
        if (allocated(accpotlst)) deallocate (accpotlst)
        allocate (accpotlst(maxelst,2,nacceptlocnl))
        naccpotlst = 0
        accpotlst = 0
        if (allocated(nlppotlst)) deallocate (nlppotlst)
        allocate (nlppotlst(nlplocnl))
        if (allocated(lppotlst)) deallocate (lppotlst)
        allocate (lppotlst(maxelst,nlplocnl))
        nlppotlst = 0
        lppotlst = 0
      end if
      
      if ((use_pmecore).and.(rank.gt.ndir-1)) return
c
      time0 = mpi_wtime()
c
c     build the cells at the beginning and assign the particules to them
c
      call build_cell_list(istep)
c
      time0 = mpi_wtime()
      if (use_clist) call clistcell
      if (use_vlist) call vlistcell
      if (use_mlist) call mlistcell
      if ((use_replist).or.(use_displist)) call replistcell
      if (use_displist) call displistcell
      if (use_ctransferlist) call ctransferlistcell
      time1 = mpi_wtime()
      timenl = timenl + time1 - time0
c
      return
      end
c
      subroutine mlistcell
      use sizes
      use atmlst
      use atoms
      use domdec
      use iounit
      use mpole
      use neigh
      use mpi
      implicit none
      integer iglob
      integer i,icell,j,k,nneigloc
      integer ineig,iipole,kkpole
      integer kcell,kloc,kglob
      integer ncell_loc
      integer, allocatable :: index(:),indcell_loc(:)
      real*8 xr,yr,zr,xi,yi,zi,xk,yk,zk,r2
      real*8, allocatable :: pos(:,:),r2vec(:)
      logical docompute
c
      allocate (index(nbloc))
      allocate (indcell_loc(nbloc))
      allocate(pos(3,nbloc))
      allocate(r2vec(nbloc))
c
c     perform a complete list build
c
      do i = 1, npolelocnl
        iipole = poleglobnl(i)
        iglob  = ipole(iipole)
        icell = repartcell(iglob)
c
c       align data of the local cell and the neighboring ones
c
        ncell_loc = cell_len(icell)
        indcell_loc(1:ncell_loc) = 
     $  indcell(bufbegcell(icell):(bufbegcell(icell)+cell_len(icell)-1))
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          indcell_loc(ncell_loc+1:(ncell_loc+cell_len(kcell))) = 
     $  indcell(bufbegcell(kcell):(bufbegcell(kcell)+cell_len(kcell)-1))
          ncell_loc = ncell_loc + cell_len(kcell)
        end do
c
c       do the neighbor search
c
        nneigloc = 0 
        xi = x(iglob)
        yi = y(iglob)
        zi = z(iglob)
        do k = 1, ncell_loc
          kglob = indcell_loc(k)
          kkpole = pollist(kglob)
c
c   skip atom if it is not in the multipole list
c
          if (kkpole.eq.0) cycle
          if (kglob.le.iglob) cycle
          xk = x(kglob)
          yk = y(kglob)
          zk = z(kglob)
          pos(1,nneigloc+1) = xi - xk
          pos(2,nneigloc+1) = yi - yk
          pos(3,nneigloc+1) = zi - zk
          call midpointimage(xi,yi,zi,xk,yk,zk,pos(1,nneigloc+1),
     $       pos(2,nneigloc+1),pos(3,nneigloc+1),docompute)
          if (docompute) then
            nneigloc = nneigloc + 1
            index(nneigloc) = kglob
          end if
        end do
c
c       compute the distances and build the list accordingly
c
        r2vec(1:nneigloc) = pos(1,1:nneigloc)*pos(1,1:nneigloc) + 
     $      pos(2,1:nneigloc)*pos(2,1:nneigloc) + 
     $      pos(3,1:nneigloc)*pos(3,1:nneigloc)
        
        j = 0
        do k = 1, nneigloc
          r2 = r2vec(k)
          kglob = index(k)
          if (r2 .le. mbuf2) then
             j = j + 1
             kkpole = pollist(kglob)
             elst(j,i) = kkpole
          end if
        end do
        nelst(i) = j
c
c     check to see if the neighbor list is too long
c
        if (nelst(i) .ge. maxelst) then
           if (rank.eq.0) then
             write (iout,10)
   10        format (/,' MBUILD  --  Too many Neighbors;',
     &                  ' Increase MAXELST')
             call fatal
           end if
        end if
      end do
c     
      deallocate (pos)
      deallocate (index)
      deallocate (indcell_loc)
      deallocate (r2vec)
      return
      end
c
c    subroutine initmpipme : build the arrays to communicate direct and reciprocal fields
c    during the calculation of the induced dipoles
c
c
      subroutine initmpipme
      use atmlst
      use domdec
      use mpole
      use pme
      use mpi
      implicit none
      integer ierr,iipole
      integer i,iproc,tag,iglob
      integer count1
      integer status(MPI_STATUS_SIZE)
      integer, allocatable :: req(:),req2(:),count(:)
      allocate (req(nproc*nproc))
      allocate (req2(nproc*nproc))
      allocate (count(nproc))
c
      count = 0 
c
c     deal with Direct-Recip communications
c
      if (allocated(buf1)) deallocate (buf1)
      allocate (buf1(nblocrecdir))
      buf1 = 0
      if (allocated(buf2)) deallocate (buf2)
      allocate (buf2(nblocrecdir))
      buf2 = 0
      if (allocated(buflen1)) deallocate (buflen1)
      allocate (buflen1(nproc))
      buflen1 = 0
      if (allocated(buflen2)) deallocate (buflen2)
      allocate (buflen2(nproc))
      buflen2 = 0
      if (allocated(bufbeg1)) deallocate (bufbeg1)
      allocate (bufbeg1(nproc))
      bufbeg1 = 0
      if (allocated(bufbeg2)) deallocate (bufbeg2)
      allocate (bufbeg2(nproc))
      bufbeg2 = 0
c
      do i = 1, npolerecloc
        iipole = polerecglob(i)
        iglob = ipole(iipole)
        if (repart(iglob).ne.rank) then
          buflen2(repart(iglob)+1) = buflen2(repart(iglob)+1)+1
        end if
      end do
      count1 = 0
      do iproc = 1, nrecdir_recep1
        if (precdir_recep1(iproc).ne.rank) then
          if (buflen2(precdir_recep1(iproc)+1).ne.0) then
            bufbeg2(precdir_recep1(iproc)+1) = count1 + 1
          else
            bufbeg2(precdir_recep1(iproc)+1) = 1
          end if
          count1 = count1 + buflen2(precdir_recep1(iproc)+1)
        end if
      end do
c
      do i = 1, npolerecloc
        iipole = polerecglob(i)
        iglob = ipole(iipole)
        if (repart(iglob).ne.rank) then
          buf2(bufbeg2(repart(iglob)+1)+count(repart(iglob)+1))=
     $      iipole
          count(repart(iglob)+1) = count(repart(iglob)+1) + 1
        end if
      end do
c
c     send and receive sizes of the buffers
c
       do i = 1, nrecdir_send1
         if (precdir_send1(i).ne.rank) then
          tag = nproc*rank + precdir_send1(i) + 1
          call MPI_IRECV(buflen1(precdir_send1(i)+1),1,MPI_INT,
     $   precdir_send1(i),tag,COMM_BEAD,req(tag),ierr)
        end if
      end do
      do i = 1, nrecdir_recep1
        if (precdir_recep1(i).ne.rank) then
          tag = nproc*precdir_recep1(i) + rank + 1
          call MPI_ISEND(buflen2(precdir_recep1(i)+1),1,MPI_INT,
     $     precdir_recep1(i),tag,COMM_BEAD,req(tag),ierr)
        end if
      end do
c
      do i = 1, nrecdir_send1
        if (precdir_send1(i).ne.rank) then
          tag = nproc*rank + precdir_send1(i) + 1
          call MPI_WAIT(req(tag),status,ierr)
        end if
      end do
      do i = 1, nrecdir_recep1
        if (precdir_recep1(i).ne.rank) then
          tag = nproc*precdir_recep1(i) + rank + 1
          call MPI_WAIT(req(tag),status,ierr)
        end if
      end do
      count1 = 0
      do iproc = 1, nrecdir_send1
        if (precdir_send1(iproc).ne.rank) then
          if (buflen1(precdir_send1(iproc)+1).ne.0) then
            bufbeg1(precdir_send1(iproc)+1) = count1 + 1
          else
            bufbeg1(precdir_send1(iproc)+1) = 1
          end if
          count1 = count1 + buflen1(precdir_send1(iproc)+1)
        end if
      end do
c
c     send and receive list of corresponding indexes
c
      do i = 1, nrecdir_send1
        if (precdir_send1(i).ne.rank) then
          tag = nproc*rank + precdir_send1(i) + 1
          call MPI_IRECV(buf1(bufbeg1(precdir_send1(i)+1)),
     $     buflen1(precdir_send1(i)+1),
     $     MPI_INT,precdir_send1(i),tag,COMM_BEAD,req2(tag),ierr)
        end if
      end do
      do i = 1, nrecdir_recep1
        if (precdir_recep1(i).ne.rank) then
          tag = nproc*precdir_recep1(i) + rank + 1
          call MPI_ISEND(buf2(bufbeg2(precdir_recep1(i)+1)),
     $     buflen2(precdir_recep1(i)+1),MPI_INT,precdir_recep1(i),tag,
     $     COMM_BEAD,req2(tag),ierr)
        end if
      end do
c
      do i = 1, nrecdir_send1
        if (precdir_send1(i).ne.rank) then
          tag = nproc*rank + precdir_send1(i) + 1
          call MPI_WAIT(req2(tag),status,ierr)
        end if
      end do
      do i = 1, nrecdir_recep1
        if (precdir_recep1(i).ne.rank) then
          tag = nproc*precdir_recep1(i) + rank + 1
          call MPI_WAIT(req2(tag),status,ierr)
        end if
      end do
c
      if (allocated(thetai1)) deallocate (thetai1)
      if (allocated(thetai2)) deallocate (thetai2)
      if (allocated(thetai3)) deallocate (thetai3)
      allocate (thetai1(4,bsorder,nlocrec))
      allocate (thetai2(4,bsorder,nlocrec))
      allocate (thetai3(4,bsorder,nlocrec))
      deallocate (req)
      deallocate (req2)
      deallocate (count)
      return
      end
c
c     subroutine reinitnl : get the number of particules whose nl has to be computed
c     and the allocated indexes
c
      subroutine reinitnl(istep)
      use atoms
      use domdec
      use neigh
      implicit none
      real*8 d,mbuf,vbuf,torquebuf,bigbuf
      integer iproc,i,iglob,modnl
      integer iloc,istep
c
      mbuf = sqrt(mbuf2)
      vbuf = sqrt(vbuf2) + 2.0d0
      torquebuf = mbuf + lbuffer
      if (torquebuf.gt.(vbuf)) then
        bigbuf = torquebuf
      else
        bigbuf = vbuf
      end if
c
      modnl = mod(istep,ineigup)
      if (modnl.ne.0) return
c
      if (.not.allocated(ineignl)) allocate (ineignl(n))
      ineignl = 0
      if (.not.allocated(locnl)) allocate (locnl(n))
      locnl = 0
c
      nlocnl = nloc
      ineignl(1:nloc) = glob(1:nloc)
      do i = 1, nlocnl
        iglob = ineignl(i)
        locnl(iglob) = i
      end do
c
      do iproc = 1, nbig_recep
        do i = 1, domlen(pbig_recep(iproc)+1)
          iloc = bufbeg(pbig_recep(iproc)+1)+i-1
          iglob = glob(iloc)
          call distprocpart(iglob,rank,d,.true.)
          if (d.le.(bigbuf/2)) then
            nlocnl = nlocnl + 1
            ineignl(nlocnl) = iglob
            locnl(iglob) = nlocnl
          end if
        end do
      end do
      return
      end
c
c
c     subroutine build_cell_list : build the cells in order to build the non bonded neighbor
c     lists with the cell-list method
c
      subroutine build_cell_list(istep)
      use atoms
      use bound
      use boxes
      use cutoff
      use domdec
      use iounit
      use neigh
      use mpi
      use potent
      implicit none
      integer i,proc,icell,j,k,p,q,r,istep,iglob
      integer count,iloc
      integer temp_x,temp_y,temp_z
      integer nx_cell,ny_cell,nz_cell
      integer temp,numneig,tempcell
      real*8 xmin,xmax,ymin,ymax,zmin,zmax
      real*8 lenx,leny,lenz
      real*8 mbuf,vbuf,bigbuf
      real*8 lenx_cell,leny_cell,lenz_cell
      real*8 xr,yr,zr
      real*8 eps1,eps2
      real*8 rebuf,cbuf,ctransferbuf,dispbuf,repbuf
      real*8, allocatable :: xbegcelltemp(:),ybegcelltemp(:)
      real*8, allocatable :: zbegcelltemp(:)
      real*8, allocatable :: xendcelltemp(:),yendcelltemp(:)
      real*8, allocatable :: zendcelltemp(:)
      integer, allocatable :: filledcell(:),indcelltemp(:)
      real*8 boxedge2
      logical docompute
c
c     check size of the box and cutoff for minimum image convention
c
 1000 format('Error in neigbor list: max cutoff + ',
     $   'buffer should be less than half one edge of the box')
 1010 format('Charge cutoff          = ',F14.3)
 1020 format('Multipole cutoff       = ',F14.3)
 1030 format('VDW cutoff             = ',F14.3)
 1040 format('Dispersion cutoff      = ',F14.3)
 1050 format('Repulsion cutoff       = ',F14.3)
 1060 format('Charge-Transfer cutoff = ',F14.3)
 1070 format('List buffer            = ',F14.3)
 1080 format('Imposing use of replica method for dispersion')
      boxedge2 = max(xbox2,ybox2,zbox2)
      if ((cbuf2.gt.boxedge2*boxedge2).and.(use_charge)) then
        if (rank.eq.0) then
          write(iout,1000) 
          write(iout,1010) chgcut
          write(iout,1070) lbuffer
        end if
        call fatal
      end if
      if ((use_mpole).and.(mbuf2.gt.boxedge2*boxedge2)) then
        if (rank.eq.0) then
          write(iout,1000) 
          write(iout,1020) mpolecut
          write(iout,1070) lbuffer
        end if
        call fatal
      end if
      if ((use_vdw).and.(vbuf2.gt.boxedge2*boxedge2)) then
        if (rank.eq.0) then
          write(iout,1000) 
          write(iout,1030) vdwcut
          write(iout,1070) lbuffer
        end if
        call fatal
      end if
      if ((use_repulsion).and.(repbuf2.gt.boxedge2*boxedge2)) then
        if (rank.eq.0) then
          write(iout,1000) 
          write(iout,1050) repcut
          write(iout,1070) lbuffer
        end if
        call fatal
      end if
      if ((use_ctransfer).and.(ctransferbuf2.gt.boxedge2*boxedge2)) then
        if (rank.eq.0) then
          write(iout,1000) 
          write(iout,1060) ctransfercut
          write(iout,1070) lbuffer
        end if
        call fatal
      end if
c
c     Only dispersion compatible with replica for now
c
      if ((use_dispersion).and.(dispbuf2.gt.boxedge2*boxedge2)) then
        if (rank.eq.0) then
          write(iout,1000) 
          write(iout,1040) dispcut
          write(iout,1070) lbuffer
          write(iout,1080) 
        end if
        use_replica = .true.
        call replica(dispcut)
        use_displist = .false.
      end if
c
      eps1 = 1.0d-10
      eps2 = 1.0d-8
      mbuf = sqrt(mbuf2)
      vbuf = sqrt(vbuf2)+2.0
      cbuf = sqrt(cbuf2)
      ctransferbuf = sqrt(ctransferbuf2)
      if (use_ctransfer) then
        if (use_ctpot) then 
          ctransferbuf = sqrt(ctransferbuf2)+mbuf
        else
          ctransferbuf = sqrt(ctransferbuf2)
        end if
      end if
      repbuf = sqrt(repbuf2)+2.0d0
      dispbuf = sqrt(dispbuf2)+2.0d0
      bigbuf = 0d0
      if (use_charge) bigbuf=max(bigbuf,cbuf)
      if (use_mpole) bigbuf=max(bigbuf,mbuf)
      if (use_vdw) bigbuf=max(bigbuf,vbuf)
      if ((use_dispersion).and.(.not.(use_replica)))
     $  bigbuf=max(bigbuf,dispbuf)
      if (use_repulsion) bigbuf=max(bigbuf,repbuf)
      if (use_ctransfer) bigbuf=max(bigbuf,ctransferbuf)
      bigbuf = bigbuf/2
c
c
c     divide the searching domain in cells of size the multipole cutoff
c
      xmin = xbegproc(rank+1)
      xmax = xendproc(rank+1)
      ymin = ybegproc(rank+1)
      ymax = yendproc(rank+1)
      zmin = zbegproc(rank+1)
      zmax = zendproc(rank+1)
      do i = 1, nbig_recep
        proc = pbig_recep(i)
        if (xbegproc(proc+1).le.xmin) xmin = xbegproc(proc+1)
        if (xendproc(proc+1).ge.xmax) xmax = xendproc(proc+1)
        if (ybegproc(proc+1).le.ymin) ymin = ybegproc(proc+1)
        if (yendproc(proc+1).ge.ymax) ymax = yendproc(proc+1)
        if (zbegproc(proc+1).le.zmin) zmin = zbegproc(proc+1)
        if (zendproc(proc+1).ge.zmax) zmax = zendproc(proc+1)
      end do
c
      lenx = abs(xmax-xmin)
      nx_cell = max(1,int(lenx/(bigbuf)))
      lenx_cell = lenx/nx_cell
      leny = abs(ymax-ymin)
      ny_cell = max(1,int(leny/(bigbuf)))
      leny_cell = leny/ny_cell
      lenz = abs(zmax-zmin)
      nz_cell = max(1,int(lenz/(bigbuf)))
      lenz_cell = lenz/nz_cell
      ncell_tot = nx_cell*ny_cell*nz_cell
c
      allocate (xbegcelltemp(nx_cell))
      allocate (xendcelltemp(nx_cell))
      allocate (ybegcelltemp(ny_cell))
      allocate (yendcelltemp(ny_cell))
      allocate (zbegcelltemp(nz_cell))
      allocate (zendcelltemp(nz_cell))
      if (allocated(xbegcell)) deallocate (xbegcell)
      allocate (xbegcell(ncell_tot))
      if (allocated(ybegcell)) deallocate (ybegcell)
      allocate (ybegcell(ncell_tot))
      if (allocated(zbegcell)) deallocate (zbegcell)
      allocate (zbegcell(ncell_tot))
      if (allocated(xendcell)) deallocate (xendcell)
      allocate (xendcell(ncell_tot))
      if (allocated(yendcell)) deallocate (yendcell)
      allocate (yendcell(ncell_tot))
      if (allocated(zendcell)) deallocate (zendcell)
      allocate (zendcell(ncell_tot))
      if (allocated(neigcell)) deallocate (neigcell)
      allocate (neigcell(124,ncell_tot))
      if (allocated(numneigcell)) deallocate (numneigcell)
      allocate (numneigcell(ncell_tot))
      allocate (filledcell(ncell_tot))
c
      do i = 0, nx_cell-1
        xbegcelltemp(i+1) = xmin + i*lenx_cell
        xendcelltemp(i+1) = xmin + (i+1)*lenx_cell
      end do
      do i = 0, ny_cell-1
        ybegcelltemp(i+1) = ymin + i*leny_cell
        yendcelltemp(i+1) = ymin + (i+1)*leny_cell
      end do
      do i = 0, nz_cell-1
        zbegcelltemp(i+1) = zmin + i*lenz_cell
        zendcelltemp(i+1) = zmin + (i+1)*lenz_cell
      end do
c
c     assign cell
c
      do k = 1, nz_cell
        do j = 1, ny_cell
          do i = 1, nx_cell
              icell = (k-1)*ny_cell*nx_cell+(j-1)*nx_cell+i
              xbegcell(icell) = xbegcelltemp(i)
              xendcell(icell) = xendcelltemp(i)
              ybegcell(icell) = ybegcelltemp(j)
              yendcell(icell) = yendcelltemp(j)
              zbegcell(icell) = zbegcelltemp(k)
              zendcell(icell) = zendcelltemp(k)
              numneig = 0
              filledcell = 0
              filledcell(icell) = 1
c
c              do p = -1,1
c                do q = -1,1
c                  do r = -1,1
              do p = -2,2
                do q = -2,2
                  do r = -2,2
                    if ((p.eq.0).and.(q.eq.0).and.(r.eq.0)) goto 10
c
                    temp_x = p+i
                    temp_y = q+j-1
                    temp_z = r+k-1
c                    if ((i.eq.1).and.(p.eq.-1)) temp_x = nx_cell
c                    if ((i.eq.nx_cell).and.(p.eq.1)) temp_x = 1
c                    if ((j.eq.1).and.(q.eq.-1)) temp_y = ny_cell-1
c                    if ((j.eq.ny_cell).and.(q.eq.1)) temp_y = 0
c                    if ((k.eq.1).and.(r.eq.-1)) temp_z = nz_cell-1
c                    if ((k.eq.nz_cell).and.(r.eq.1)) temp_z = 0

                    if ((i.eq.1).and.(p.eq.-2)) temp_x = nx_cell-1
                    if ((i.eq.1).and.(p.eq.-1)) temp_x = nx_cell
                    if ((i.eq.2).and.(p.eq.-2)) temp_x = nx_cell
                    if ((i.eq.nx_cell).and.(p.eq.1)) temp_x = 1
                    if ((i.eq.nx_cell).and.(p.eq.2)) temp_x = 2
                    if ((i.eq.nx_cell-1).and.(p.eq.2)) temp_x = 1
                    if ((j.eq.1).and.(q.eq.-2)) temp_y = ny_cell-2
                    if ((j.eq.1).and.(q.eq.-1)) temp_y = ny_cell-1
                    if ((j.eq.2).and.(q.eq.-2)) temp_y = ny_cell-1
                    if ((j.eq.ny_cell).and.(q.eq.1)) temp_y = 0
                    if ((j.eq.ny_cell).and.(q.eq.2)) temp_y = 1
                    if ((j.eq.ny_cell-1).and.(q.eq.2)) temp_y = 0
                    if ((k.eq.1).and.(r.eq.-2)) temp_z = nz_cell-2
                    if ((k.eq.1).and.(r.eq.-1)) temp_z = nz_cell-1
                    if ((k.eq.2).and.(r.eq.-2)) temp_z = nz_cell-1
                    if ((k.eq.nz_cell).and.(r.eq.1)) temp_z = 0
                    if ((k.eq.nz_cell).and.(r.eq.2)) temp_z = 1
                    if ((k.eq.nz_cell-1).and.(r.eq.2)) temp_z = 0
                    tempcell = temp_z*ny_cell*nx_cell+temp_y*nx_cell+
     $                temp_x
c                    write(*,*) 'tempcell = ',tempcell,i,j,k
c                    write(*,*) '******'
c                    write(*,*) 'p,q,r = ',p,q,r
                    if (filledcell(tempcell).eq.1) goto 10
                    filledcell(tempcell) = 1
                    numneig = numneig+1
                    neigcell(numneig,icell) = tempcell
 10               continue
                  end do
                end do
              end do
              numneigcell(icell) = numneig
          end do
        end do
      end do
      deallocate (filledcell)
      deallocate (xbegcelltemp)
      deallocate (xendcelltemp)
      deallocate (ybegcelltemp)
      deallocate (yendcelltemp)
      deallocate (zbegcelltemp)
      deallocate (zendcelltemp)
c
c     assign the atoms to the cells
c
      if (allocated(cell_len)) deallocate (cell_len)
      allocate (cell_len(ncell_tot))
      if (allocated(indcell)) deallocate (indcell)
      allocate (indcell(n))
      if (allocated(bufbegcell)) deallocate (bufbegcell)
      allocate (bufbegcell(ncell_tot))
      if (allocated(repartcell)) deallocate (repartcell)
      allocate (repartcell(n))
      allocate (indcelltemp(n))
      cell_len = 0
c
      do i = 1, nlocnl
        iglob = ineignl(i)
        xr = x(iglob)
        yr = y(iglob)
        zr = z(iglob)
        if (use_bounds) call image(xr,yr,zr)
        if (abs(xr-xmax).lt.eps1) xr = xr-eps2
        if (abs(yr-ymax).lt.eps1) yr = yr-eps2
        if (abs(zr-zmax).lt.eps1) zr = zr-eps2
        do icell = 1, ncell_tot
          if ((zr.ge.zbegcell(icell)).and.
     $     (zr.lt.zendcell(icell)).and.(yr.ge.ybegcell(icell))
     $    .and.(yr.lt.yendcell(icell)).and.(xr.ge.xbegcell(icell))
     $    .and.(xr.lt.xendcell(icell))) then
            repartcell(iglob) = icell
            cell_len(icell) = cell_len(icell) + 1
            indcelltemp(iglob) = cell_len(icell)
          end if
        end do
      end do
c
      bufbegcell(1) = 1
      count = cell_len(1)
      do icell = 2, ncell_tot
        if (cell_len(icell).ne.0) then
          bufbegcell(icell) = count + 1
        else
          bufbegcell(icell) = 1
        end if
        count = count + cell_len(icell)
      end do
c
      do i = 1, nlocnl
        iglob = ineignl(i)
        icell = repartcell(iglob)
        iloc  = bufbegcell(icell) + indcelltemp(iglob) - 1
        indcell(iloc) = iglob
      end do
      deallocate (indcelltemp)
      return
      end
c
c    "clistcellvec" performs a complete rebuild of the
c     electrostatic neighbor lists for charges using linked cells method
c
      subroutine clistcell
      use sizes
      use atmlst
      use atoms
      use charge
      use domdec
      use iounit
      use neigh
      use mpi
      implicit none
      integer iglob
      integer i,icell,j,k,nneigloc
      integer ineig,iichg,kkchg
      integer kcell,kloc,kglob
      integer ncell_loc
      integer, allocatable :: index(:),indcell_loc(:)
      real*8 xr,yr,zr,xi,yi,zi,xk,yk,zk,r2
      real*8, allocatable :: pos(:,:),r2vec(:)
      logical docompute
c
      allocate (index(nbloc))
      allocate (indcell_loc(nbloc))
      allocate(pos(3,nbloc))
      allocate(r2vec(nbloc))
c
c     perform a complete list build
c
      do i = 1, nionlocnl
        iichg = chgglobnl(i)
        iglob  = iion(iichg)
        icell = repartcell(iglob)
c
c       align data of the local cell and the neighboring ones
c
        ncell_loc = cell_len(icell)
        indcell_loc(1:ncell_loc) = 
     $  indcell(bufbegcell(icell):(bufbegcell(icell)+cell_len(icell)-1))
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          indcell_loc(ncell_loc+1:(ncell_loc+cell_len(kcell))) = 
     $  indcell(bufbegcell(kcell):(bufbegcell(kcell)+cell_len(kcell)-1))
          ncell_loc = ncell_loc + cell_len(kcell)
        end do
c
c       do the neighbor search
c
        nneigloc = 0 
        xi = x(iglob)
        yi = y(iglob)
        zi = z(iglob)
        do k = 1, ncell_loc
          kglob = indcell_loc(k)
          kkchg = chglist(kglob)
          if (kkchg.eq.0) cycle
          if (kglob.le.iglob) cycle
          xk = x(kglob)
          yk = y(kglob)
          zk = z(kglob)
          pos(1,nneigloc+1) = xi - xk
          pos(2,nneigloc+1) = yi - yk
          pos(3,nneigloc+1) = zi - zk
          call midpointimage(xi,yi,zi,xk,yk,zk,pos(1,nneigloc+1),
     $       pos(2,nneigloc+1),pos(3,nneigloc+1),docompute)
          if (docompute) then
            nneigloc = nneigloc + 1
            index(nneigloc) = kglob
          end if
        end do
c
c       compute the distances and build the list accordingly
c
        r2vec(1:nneigloc) = pos(1,1:nneigloc)*pos(1,1:nneigloc) + 
     $      pos(2,1:nneigloc)*pos(2,1:nneigloc) + 
     $      pos(3,1:nneigloc)*pos(3,1:nneigloc)
        
        j = 0
        do k = 1, nneigloc
          r2 = r2vec(k)
          kglob = index(k)
          if (r2 .le. cbuf2) then
             j = j + 1
             kkchg = chglist(kglob)
             elst(j,i) = kkchg
          end if
        end do
        nelst(i) = j
c
c     check to see if the neighbor list is too long
c
        if (nelst(i) .ge. maxelst) then
           if (rank.eq.0) then
             write (iout,10)
   10        format (/,' MBUILD  --  Too many Neighbors;',
     &                  ' Increase MAXELST')
             call fatal
           end if
        end if
      end do
c     
      deallocate (pos)
      deallocate (index)
      deallocate (indcell_loc)
      deallocate (r2vec)
      return
      end
c
c    "vlistcell" performs a complete rebuild of the
c     vdw neighbor lists for charges using linked cells method
c
      subroutine vlistcell
      use atmlst
      use atoms
      use domdec
      use iounit
      use kvdws
      use neigh
      use vdw
      use mpi
      implicit none
      integer iglob,iloc
      integer i,ii,icell,j,k,nneigloc
      integer ineig,iivdw,iv
      integer kcell,kloc,kglob,kbis
      integer ncell_loc
      integer, allocatable :: index(:),indcell_loc(:)
      real*8 xr,yr,zr,xi,yi,zi,xk,yk,zk,r2,rdn
      real*8, allocatable :: pos(:,:),r2vec(:)
      real*8, allocatable :: xred(:)
      real*8, allocatable :: yred(:)
      real*8, allocatable :: zred(:)
      logical docompute
c
      allocate (xred(nbloc))
      allocate (yred(nbloc))
      allocate (zred(nbloc))
c
      allocate (index(nbloc))
      allocate (indcell_loc(nbloc))
      allocate(pos(3,nbloc))
      allocate(r2vec(nbloc))
c
c     apply reduction factors to find coordinates for each site
c
      do ii = 1, nvdwbloc
         iivdw = vdwglob(ii)
         iglob = ivdw(iivdw)
         i = loc(iglob)
         iv = ired(iglob)
         rdn = kred(iglob)
         xred(i) = rdn*(x(iglob)-x(iv)) + x(iv)
         yred(i) = rdn*(y(iglob)-y(iv)) + y(iv)
         zred(i) = rdn*(z(iglob)-z(iv)) + z(iv)
      end do
c
c     perform a complete list build
c
      do i = 1, nvdwlocnl
        iivdw = vdwglobnl(i)
        iglob  = ivdw(iivdw)
        icell = repartcell(iglob)
        iloc = loc(iglob)
c
c       align data of the local cell and the neighboring ones
c
        ncell_loc = cell_len(icell)
        indcell_loc(1:ncell_loc) = 
     $  indcell(bufbegcell(icell):(bufbegcell(icell)+cell_len(icell)-1))
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          indcell_loc(ncell_loc+1:(ncell_loc+cell_len(kcell))) = 
     $  indcell(bufbegcell(kcell):(bufbegcell(kcell)+cell_len(kcell)-1))
          ncell_loc = ncell_loc + cell_len(kcell)
        end do
c
c       do the neighbor search
c
        nneigloc = 0 
        xi = xred(iloc)
        yi = yred(iloc)
        zi = zred(iloc)
        do k = 1, ncell_loc
          kglob = indcell_loc(k)
          if (kglob.le.iglob) cycle
          if (rad(jvdw(kglob)).eq.0) cycle
          kbis = loc(kglob)
          xk = xred(kbis)
          yk = yred(kbis)
          zk = zred(kbis)
          pos(1,nneigloc+1) = xi - xk
          pos(2,nneigloc+1) = yi - yk
          pos(3,nneigloc+1) = zi - zk
          call midpointimage(xi,yi,zi,xk,yk,zk,pos(1,nneigloc+1),
     $       pos(2,nneigloc+1),pos(3,nneigloc+1),docompute)
          if (docompute) then
            nneigloc = nneigloc + 1
            index(nneigloc) = kglob
          end if
        end do
c
c       compute the distances and build the list accordingly
c
        r2vec(1:nneigloc) = pos(1,1:nneigloc)*pos(1,1:nneigloc) + 
     $      pos(2,1:nneigloc)*pos(2,1:nneigloc) + 
     $      pos(3,1:nneigloc)*pos(3,1:nneigloc)
        
        j = 0
        do k = 1, nneigloc
          r2 = r2vec(k)
          kglob = index(k)
          if (r2 .le. vbuf2) then
             j = j + 1
             vlst(j,i) = kglob
          end if
        end do
        nvlst(i) = j
c
c     check to see if the neighbor list is too long
c
        if (nvlst(i) .ge. maxvlst) then
           if (rank.eq.0) then
             write (iout,10)
   10        format (/,' VBUILD  --  Too many Neighbors;',
     &                  ' Increase MAXVLST')
             call fatal
           end if
        end if
      end do
c     
      deallocate (xred)
      deallocate (yred)
      deallocate (zred)
c
      deallocate (pos)
      deallocate (index)
      deallocate (indcell_loc)
      deallocate (r2vec)
      return
      end
c
c    "replistcell" performs a complete rebuild of the
c     repulsion neighbor lists using linked cells method
c
      subroutine replistcell
      use sizes
      use atoms
      use atmlst
      use bound
      use chargetransfer
      use couple
      use domdec
      use iounit
      use bond
      use neigh
      use potent
      use mpi
      implicit none
      integer modnl,ierr
      integer i,proc,icell,j,k,l
      integer ineig,temp,numneig,tempcell
      integer ibond,jbond,i1,i2
      integer kcell,kloc,kglob,lglob
      integer ilp,klp,ilpat
      integer count
      real*8 xbond1,ybond1,zbond1,xbond2,ybond2,zbond2
      real*8 x1lp,y1lp,z1lp,x2lp,y2lp,z2lp
      real*8 x1,y1,z1,x2,y2,z2
      real*8 xr,yr,zr,r2
      logical docompute
c
c     perform a complete bond-bond list build
c
      do i = 1, nbondlocnl
        j = 0
        ibond = bondglobnl(i)
        i1 = ibnd(1,ibond)
        i2 = ibnd(2,ibond)
        xbond1 = (x(i1) + x(i2))/2
        ybond1 = (y(i1) + y(i2))/2
        zbond1 = (z(i1) + z(i2))/2
        icell = repartcell(i1)
c
c      search in the same cell
c
        do k = 1, cell_len(icell)
          kloc = bufbegcell(icell)+k-1
          kglob = indcell(kloc)
          do l = 1, n12(kglob)
            lglob = i12(l,kglob)
c
c      avoid double counting of the bonds
c
            if (lglob.le.kglob) cycle
c            call midpoint(x(kglob),y(kglob),z(kglob),x(lglob),
c     $        y(lglob),z(lglob),docompute)
c            if (.not.(docompute)) cycle
            jbond = bndlist(l,kglob)
            if (jbond.le.ibond) cycle
            xbond2 = (x(kglob) + x(lglob))/2
            ybond2 = (y(kglob) + y(lglob))/2
            zbond2 = (z(kglob) + z(lglob))/2
            call midpoint(xbond1,ybond1,zbond1,xbond2,ybond2,zbond2,
     $        docompute)
            if (docompute) then
              xr = xbond1 - xbond2
              yr = ybond1 - ybond2
              zr = zbond1 - zbond2
              call image (xr,yr,zr)
              r2 = xr*xr + yr*yr + zr*zr
              if (r2 .le. repbuf2) then
                 j = j + 1
                 bondlst(j,i) = bndlist(l,kglob)
              end if
            end if
          end do
        end do
c
c      search in the neighboring cells
c
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          do k = 1, cell_len(kcell)
            kloc = bufbegcell(kcell)+k-1
            kglob = indcell(kloc)
            do l = 1, n12(kglob)
              lglob = i12(l,kglob)
c
c      avoid double counting of the bonds
c
            if (lglob.le.kglob) cycle
            jbond = bndlist(l,kglob)
            if (jbond.le.ibond) cycle
              xbond2 = (x(kglob) + x(lglob))/2
              ybond2 = (y(kglob) + y(lglob))/2
              zbond2 = (z(kglob) + z(lglob))/2
              call midpoint(xbond1,ybond1,zbond1,xbond2,ybond2,zbond2,
     $          docompute)
              if (docompute) then
                xr = xbond1 - xbond2
                yr = ybond1 - ybond2
                zr = zbond1 - zbond2
                call image (xr,yr,zr)
                r2 = xr*xr + yr*yr + zr*zr
                if (r2 .le. repbuf2) then
                   j = j + 1
                   bondlst(j,i) = bndlist(l,kglob)
                end if
              end if
            end do
          end do
        end do
        nbondlst(i) = j
c
c     check to see if the neighbor list is too long
c
        if (nbondlst(i) .ge. maxbondlst) then
           if (rank.eq.0) then
             write (iout,10)
   10        format (/,' REPLISTCELL  --  Too many Neighbors;',
     &                  ' Increase MAXBONDLST')
             call fatal
           end if
        end if
      end do
c
c     perform a complete bond-lp list build
c
      do i = 1, nbondlocnl
        j = 0
        ibond = bondglobnl(i)
        i1 = ibnd(1,ibond)
        i2 = ibnd(2,ibond)
        xbond1 = (x(i1) + x(i2))/2
        ybond1 = (y(i1) + y(i2))/2
        zbond1 = (z(i1) + z(i2))/2
        icell = repartcell(i1)
c
c      search in the same cell
c
        do k = 1, cell_len(icell)
          kloc = bufbegcell(icell) + k - 1
          kglob = indcell(kloc)
          do l = 1, nilplst(kglob)
            klp = ilplst(l,kglob)
            x2lp = rlonepair(1,klp) 
            y2lp = rlonepair(2,klp) 
            z2lp = rlonepair(3,klp) 
            call midpoint(xbond1,ybond1,zbond1,x2lp,y2lp,z2lp,
     $        docompute)
            if (docompute) then
              xr = xbond1 - x2lp
              yr = ybond1 - y2lp
              zr = zbond1 - z2lp
              call image (xr,yr,zr)
              r2 = xr*xr + yr*yr + zr*zr
              if (r2 .le. repbuf2) then
                 j = j + 1
                 bondlplst(j,i) = klp
              end if
            end if
          end do
        end do
c
c      search in the neighboring cells
c
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          do k = 1, cell_len(kcell)
            kloc = bufbegcell(kcell) + k - 1
            kglob = indcell(kloc)
            do l = 1, nilplst(kglob)
              klp = ilplst(l,kglob)
              x2lp = rlonepair(1,klp) 
              y2lp = rlonepair(2,klp) 
              z2lp = rlonepair(3,klp) 
              call midpoint(xbond1,ybond1,zbond1,x2lp,y2lp,z2lp,
     $        docompute)
              if (docompute) then
                xr = xbond1 - x2lp
                yr = ybond1 - y2lp
                zr = zbond1 - z2lp
                call image (xr,yr,zr)
                r2 = xr*xr + yr*yr + zr*zr
                if (r2 .le. repbuf2) then
                   j = j + 1
                   bondlplst(j,i) = klp
                end if
              end if
            end do
          end do
        end do
        nbondlplst(i) = j
c
c     check to see if the neighbor list is too long
c
        if (nbondlst(i) .ge. maxbondlst) then
           if (rank.eq.0) then
             write (iout,20)
   20        format (/,' REPLISTCELL  --  Too many Neighbors;',
     &                  ' Increase MAXBONDLST')
             call fatal
           end if
        end if
      end do
c
c     perform a complete lp-lp list build
c
      do i = 1, nlplocnl
        j = 0
        ilp = lpglobnl(i)
        x1lp = rlonepair(1,ilp)
        y1lp = rlonepair(2,ilp)
        z1lp = rlonepair(3,ilp)
        ilpat = lpatom(ilp)
        icell = repartcell(ilpat)
c
c      search in the same cell
c
        do k = 1, cell_len(icell)
          kloc = bufbegcell(icell) + k - 1
          kglob = indcell(kloc)
          do l = 1, nilplst(kglob)
            klp = ilplst(l,kglob)
            x2lp = rlonepair(1,klp) 
            y2lp = rlonepair(2,klp) 
            z2lp = rlonepair(3,klp) 
            if (klp.le.ilp) cycle
            call midpoint(x1lp,y1lp,z1lp,x2lp,y2lp,z2lp,
     $        docompute)
            if (docompute) then
              xr = x1lp - x2lp
              yr = y1lp - y2lp
              zr = z1lp - z2lp
              call image (xr,yr,zr)
              r2 = xr*xr + yr*yr + zr*zr
              if (r2 .le. max(repbuf2,dispbuf2)) then
                 j = j + 1
                 lplplst(j,i) = klp
              end if
            end if
          end do
        end do
c
c      search in the neighboring cells
c
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          do k = 1, cell_len(kcell)
            kloc = bufbegcell(kcell) + k - 1
            kglob = indcell(kloc)
            do l = 1, nilplst(kglob)
              klp = ilplst(l,kglob)
              if (klp.le.ilp) cycle
              x2lp = rlonepair(1,klp) 
              y2lp = rlonepair(2,klp) 
              z2lp = rlonepair(3,klp) 
              call midpoint(x1lp,y1lp,z1lp,x2lp,y2lp,z2lp,
     $        docompute)
              if (docompute) then
                xr = x1lp - x2lp
                yr = y1lp - y2lp
                zr = z1lp - z2lp
                call image (xr,yr,zr)
                r2 = xr*xr + yr*yr + zr*zr
                if (r2 .le. max(repbuf2,dispbuf2)) then
                   j = j + 1
                   lplplst(j,i) = klp
                end if
              end if
            end do
          end do
        end do
        nlplplst(i) = j
c
c     check to see if the neighbor list is too long
c
        if (nlplplst(i) .ge. maxlplst) then
           if (rank.eq.0) then
             write (iout,40)
   40        format (/,' REPLISTCELL  --  Too many Neighbors;',
     &                  ' Increase MAXLPLST')
             call fatal
           end if
        end if
      end do
      return
      end
c
c    "displistcell" performs a complete rebuild of the
c     dispersion neighbor lists using linked cells method
c
      subroutine displistcell
      use sizes
      use atoms
      use atmlst
      use bound
      use couple
      use domdec
      use iounit
      use chargetransfer
      use neigh
      use potent
      use mpi
      implicit none
      integer modnl
      integer i,proc,icell,j,k,l,iglob
      integer ineig,temp,numneig,tempcell
      integer kcell,kloc,kglob,lglob
      integer ilp,klp,ilpat
      integer count
      real*8 xi,yi,zi,xk,yk,zk,x2lp,y2lp,z2lp,x1lp,y1lp,z1lp
      real*8 xr,yr,zr,r2
      logical docompute
c
c     perform a complete lp-atom list build
c
      do i = 1, nlplocnl
        j = 0
        ilp = lpglobnl(i)
        x1lp = rlonepair(1,ilp)
        y1lp = rlonepair(2,ilp)
        z1lp = rlonepair(3,ilp)
        ilpat = lpatom(ilp)
        icell = repartcell(ilpat)
c
c      search in the same cell
c
        do k = 1, cell_len(icell)
          kloc = bufbegcell(icell) + k - 1
          kglob = indcell(kloc)
          xk = x(kglob)
          yk = y(kglob)
          zk = z(kglob)
          call midpoint(x1lp,y1lp,z1lp,xk,yk,zk,docompute)
          if (docompute) then
            xr = x1lp - xk
            yr = y1lp - yk
            zr = z1lp - zk
            call image (xr,yr,zr)
            r2 = xr*xr + yr*yr + zr*zr
            if (r2 .le. dispbuf2) then
               j = j + 1
               lpatlst(j,i) = kglob
            end if
          end if
        end do
c
c      search in the neighboring cells
c
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          do k = 1, cell_len(kcell)
            kloc = bufbegcell(kcell) + k - 1
            kglob = indcell(kloc)
            xk = x(kglob)
            yk = y(kglob)
            zk = z(kglob)
            call midpoint(x1lp,y1lp,z1lp,xk,yk,zk,docompute)
            if (docompute) then
              xr = x1lp - xk
              yr = y1lp - yk
              zr = z1lp - zk
              call image (xr,yr,zr)
              r2 = xr*xr + yr*yr + zr*zr
              if (r2 .le. dispbuf2) then
                 j = j + 1
                 lpatlst(j,i) = kglob
              end if
            end if
          end do
        end do
        nlpatlst(i) = j
c
c     check to see if the neighbor list is too long
c
        if (nlpatlst(i) .ge. maxlplst) then
           if (rank.eq.0) then
             write (iout,10)
   10        format (/,' DISPLISTCELL  --  Too many Neighbors;',
     &                  ' Increase MAXLPLST')
             call fatal
           end if
        end if
      end do
c
c     perform a complete atom-atom list build
c
      do i = 1, nlocnl
        j = 0
        iglob = ineignl(i)
        icell = repartcell(iglob)
        xi = x(iglob)
        yi = y(iglob)
        zi = z(iglob)
c
c      search in the same cell
c
        do k = 1, cell_len(icell)
          kloc = bufbegcell(icell) + k - 1
          kglob = indcell(kloc)
          xk = x(kglob)
          yk = y(kglob)
          zk = z(kglob)
          if (kglob.le.iglob) cycle
          call midpoint(xi,yi,zi,xk,yk,zk,docompute)
          if (docompute) then
            xr = xi - xk
            yr = yi - yk
            zr = zi - zk
            call image (xr,yr,zr)
            r2 = xr*xr + yr*yr + zr*zr
            if (r2 .le. dispbuf2) then
               j = j + 1
               atatlst(j,i) = kglob
            end if
          end if
        end do
c
c      search in the neighboring cells
c
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          do k = 1, cell_len(kcell)
            kloc = bufbegcell(kcell) + k - 1
            kglob = indcell(kloc)
            xk = x(kglob)
            yk = y(kglob)
            zk = z(kglob)
            if (kglob.le.iglob) cycle
            call midpoint(xi,yi,zi,xk,yk,zk,docompute)
            if (docompute) then
              xr = xi - xk
              yr = yi - yk
              zr = zi - zk
              call image (xr,yr,zr)
              r2 = xr*xr + yr*yr + zr*zr
              if (r2 .le. dispbuf2) then
                 j = j + 1
                 atatlst(j,i) = kglob
              end if
            end if
          end do
        end do
        natatlst(i) = j
c
c     check to see if the neighbor list is too long
c
        if (natatlst(i) .ge. maxatlst) then
           if (rank.eq.0) then
             write (iout,30)
   30        format (/,' MBUILD  --  Too many Neighbors;',
     &                  ' Increase MAXATLST')
             call fatal
           end if
        end if
      end do
      return
      end
c
c    "ctransferlistcell" performs a complete rebuild of the
c     charge transfer neighbor lists using linked cells method
c
      subroutine ctransferlistcell
      use sizes
      use atoms
      use atmlst
      use atmtyp
      use bound
      use couple
      use domdec
      use iounit
      use chargetransfer
      use mpole
      use neigh
      use potent
      use mpi
      implicit none
      integer modnl
      integer i,proc,icell,j,k,l,m,iglob,iaccept
      integer i1,i2,iipole
      integer ineig,temp,numneig,tempcell
      integer kcell,kloc,kglob,lglob,kaccept
      integer ilp,klp,ilpat,m1,m2
      integer iacc,k1,k2,kkpole
      integer count
      real*8 xi,yi,zi,xk,yk,zk,x2lp,y2lp,z2lp,xa,ya,za
      real*8 xl,yl,zl
      real*8 xr,yr,zr,r2
      logical docompute
c
c     perform a complete lp-acceptor list build
c
      do i = 1, nlplocnl
        j = 0
        ilp = lpglobnl(i)
        ilpat = lpatom(ilp)
        xa = x(ilpat) 
        ya = y(ilpat) 
        za = z(ilpat) 
        icell = repartcell(ilpat)
        
c
c      search in the same cell
c
        do k = 1, cell_len(icell)
          kloc = bufbegcell(icell) + k - 1
          kglob = indcell(kloc)
          if (atomic(kglob).ne.1) cycle
          kaccept = acceptlist(kglob)
          if (kaccept.eq.0) cycle
          l = acceptor(1,kaccept)
          xk = x(l)
          yk = y(l)
          zk = z(l)
          m = acceptor(2,kaccept)
          if ((l.eq.ilpat).or.(m.eq.ilpat)) cycle
c
          call midpoint(xa,ya,za,xk,yk,zk,docompute)
          if (docompute) then
            xr = xa - xk
            yr = ya - yk
            zr = za - zk
            call image (xr,yr,zr)
            r2 = xr*xr + yr*yr + zr*zr
            if (r2 .le. ctransferbuf2) then
               j = j + 1
               lpacclst(j,i) = kaccept
            end if
          end if
        end do
c
c      search in the neighboring cells
c
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          do k = 1, cell_len(kcell)
            kloc = bufbegcell(kcell) + k - 1
            kglob = indcell(kloc)
            if (atomic(kglob).ne.1) cycle
            kaccept = acceptlist(kglob)
            if (kaccept.eq.0) cycle
            l = acceptor(1,kaccept)
            xk = x(l)
            yk = y(l)
            zk = z(l)
            m = acceptor(2,kaccept)
            if ((l.eq.ilpat).or.(m.eq.ilpat)) cycle
c
            call midpoint(xa,ya,za,xk,yk,zk,docompute)
            if (docompute) then
              xr = xa - xk
              yr = ya - yk
              zr = za - zk
              call image (xr,yr,zr)
              r2 = xr*xr + yr*yr + zr*zr
              if (r2 .le. ctransferbuf2) then
                 j = j + 1
                 lpacclst(j,i) = kaccept
              end if
            end if
          end do
        end do
        nlpacclst(i) = j
c
c     check to see if the neighbor list is too long
c
        if (nlpacclst(i) .ge. maxlplst) then
           if (rank.eq.0) then
             write (iout,10)
   10        format (/,' CTRANSFERLISTCELL  --  Too many Neighbors;',
     &                  ' Increase MAXLPLST')
             call fatal
           end if
        end if
      end do
c
c
      if (.not.(use_ctpot)) return
c
c     build the neighbor list to get the electrostatic potential on the
c     acceptors of the system
c
c     perform a complete list build
c
      do i = 1, nacceptlocnl
        j = 0
        iacc = acceptglobnl(i)
        i1 = acceptor(1,iacc)
        i2 = acceptor(2,iacc)
        iipole = pollist(i1)
        icell = repartcell(i1)
        xi = x(i1)
        yi = y(i1)
        zi = z(i1)
c
c      search in the same cell
c
        do k = 1, cell_len(icell)
          kloc = bufbegcell(icell) + k - 1
          kglob = indcell(kloc)
          kkpole = pollist(kglob)
c
c   skip atom if it is not in the multipole list
c
          if (kkpole.eq.0) cycle
          xk = x(kglob)
          yk = y(kglob)
          zk = z(kglob)
          call midpoint(xi,yi,zi,xk,yk,zk,docompute)
          if (docompute) then
            xr = xi - xk
            yr = yi - yk
            zr = zi - zk
            call image (xr,yr,zr)
            r2 = xr*xr + yr*yr + zr*zr
            if (r2 .le. mpolectbuf2) then
               j = j + 1
               accpotlst(j,1,i) = kkpole
            end if
          end if
        end do
c
c      search in the neighboring cells
c
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          do k = 1, cell_len(kcell)
            kloc = bufbegcell(kcell) + k - 1
            kglob = indcell(kloc)
            kkpole = pollist(kglob)
c
c   skip atom if it is not in the multipole list
c
            if (kkpole.eq.0) cycle
            xk = x(kglob)
            yk = y(kglob)
            zk = z(kglob)
            call midpoint(xi,yi,zi,xk,yk,zk,docompute)
            if (docompute) then
              xr = xi - xk
              yr = yi - yk
              zr = zi - zk
              call image (xr,yr,zr)
              r2 = xr*xr + yr*yr + zr*zr
              if (r2 .le. mpolectbuf2) then
                 j = j + 1
                 accpotlst(j,1,i) = kkpole
              end if
            end if
          end do
        end do
        naccpotlst(1,i) = j
c
        j = 0
        iipole = pollist(i2)
        icell = repartcell(i2)
        xi = x(i2)
        yi = y(i2)
        zi = z(i2)
c
c      search in the same cell
c
        do k = 1, cell_len(icell)
          kloc = bufbegcell(icell) + k - 1
          kglob = indcell(kloc)
          kkpole = pollist(kglob)
c
c   skip atom if it is not in the multipole list
c
          if (kkpole.eq.0) cycle
          xk = x(kglob)
          yk = y(kglob)
          zk = z(kglob)
          call midpoint(xi,yi,zi,xk,yk,zk,docompute)
          if (docompute) then
            xr = xi - xk
            yr = yi - yk
            zr = zi - zk
            call image (xr,yr,zr)
            r2 = xr*xr + yr*yr + zr*zr
            if (r2 .le. mpolectbuf2) then
               j = j + 1
               accpotlst(j,2,i) = kkpole
            end if
          end if
        end do
c
c      search in the neighboring cells
c
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          do k = 1, cell_len(kcell)
            kloc = bufbegcell(kcell) + k - 1
            kglob = indcell(kloc)
            kkpole = pollist(kglob)
c
c   skip atom if it is not in the multipole list
c
            if (kkpole.eq.0) cycle
            xk = x(kglob)
            yk = y(kglob)
            zk = z(kglob)
            call midpoint(xi,yi,zi,xk,yk,zk,docompute)
            if (docompute) then
              xr = xi - xk
              yr = yi - yk
              zr = zi - zk
              call image (xr,yr,zr)
              r2 = xr*xr + yr*yr + zr*zr
              if (r2 .le. mpolectbuf2) then
                 j = j + 1
                 accpotlst(j,2,i) = kkpole
              end if
            end if
          end do
        end do
        naccpotlst(2,i) = j
      end do
c
c     build the neighbor list to get the electrostatic potential on the
c     electron donnors of the system
c
c     perform a complete list build
c
      do i = 1, nlplocnl
        j = 0
        ilp = lpglobnl(i)
        iglob = lpatom(ilp)
        iipole = pollist(iglob)
        icell = repartcell(i1)
        xi = x(iglob)
        yi = y(iglob)
        zi = z(iglob)
c
c      search in the same cell
c
        do k = 1, cell_len(icell)
          kloc = bufbegcell(icell) + k - 1
          kglob = indcell(kloc)
          kkpole = pollist(kglob)
c
c   skip atom if it is not in the multipole list
c
          if (kkpole.eq.0) cycle
          xk = x(kglob)
          yk = y(kglob)
          zk = z(kglob)
          call midpoint(xi,yi,zi,xk,yk,zk,docompute)
          if (docompute) then
            xr = xi - xk
            yr = yi - yk
            zr = zi - zk
            call image (xr,yr,zr)
            r2 = xr*xr + yr*yr + zr*zr
            if (r2 .le. mpolectbuf2) then
               j = j + 1
               lppotlst(j,i) = kkpole
            end if
          end if
        end do
c
c      search in the neighboring cells
c
        do ineig = 1, numneigcell(icell)
          kcell = neigcell(ineig,icell)
          do k = 1, cell_len(kcell)
            kloc = bufbegcell(kcell) + k - 1
            kglob = indcell(kloc)
            kkpole = pollist(kglob)
c
c   skip atom if it is not in the multipole list
c
            if (kkpole.eq.0) cycle
            xk = x(kglob)
            yk = y(kglob)
            zk = z(kglob)
            call midpoint(xi,yi,zi,xk,yk,zk,docompute)
            if (docompute) then
              xr = xi - xk
              yr = yi - yk
              zr = zi - zk
              call image (xr,yr,zr)
              r2 = xr*xr + yr*yr + zr*zr
              if (r2 .le. mpolectbuf2) then
                 j = j + 1
                 lppotlst(j,i) = kkpole
              end if
            end if
          end do
        end do
        nlppotlst(i) = j
      end do
      return
      end
