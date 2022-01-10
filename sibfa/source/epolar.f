c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     #################################################################
c     ##                                                             ##
c     ##  subroutine epolar  --  induced dipole polarization energy  ##
c     ##                                                             ##
c     #################################################################
c
c
c     "epolar" calculates the polarization energy due to induced
c     dipole interactions
c
c
      subroutine epolar
      implicit none
c
      call epolar0c
      return
      end
c
c     ###################################################################
c     ##                                                               ##
c     ##  subroutine epolar0c  --  Ewald polarization derivs via list  ##
c     ##                                                               ##
c     ###################################################################
c
c
c     "epolar0c" calculates the dipole polarization energy with respect
c     to Cartesian coordinates using particle mesh Ewald summation and
c     a neighbor list
c
c
      subroutine epolar0c
      use sizes
      use atmlst
      use atoms
      use boxes
      use chgpot
      use domdec
      use energi
      use ewald
      use math
      use mpole
      use polar
      use polpot
      use potent
      use mpi
      implicit none
      integer i,ii,iglob,iipole
      real*8 e,f,term,fterm
      real*8 dix,diy,diz
      real*8 uix,uiy,uiz,uii
      real*8 xd,yd,zd
      real*8 xu,yu,zu
c
c
c     zero out the polarization energy and derivatives
c
      ep = 0.0d0
      if (npole .eq. 0)  return
c
c     set the energy unit conversion factor
c
      f = electric / dielec
c
c     check the sign of multipole components at chiral sites
c
      if (.not. use_mpole)  call chkpole
c
c     rotate the multipole components into the global frame
c
      if (.not. use_mpole)  call rotpole
c
c     compute the induced dipoles at each polarizable atom
c
      if (use_pmecore) then
        if (polalg.eq.5) then
          call dcinduce_pme
        else
          call newinduce_pme
        end if
      else
        if (polalg.eq.5) then
          call dcinduce_pme2
        else
          call newinduce_pme2
        end if
      end if
c
c     compute the reciprocal space part of the Ewald summation
c
      if ((.not.(use_pmecore)).or.(use_pmecore).and.(rank.gt.ndir-1))
     $  call eprecip
c
c     compute the real space part of the Ewald summation
c
      if ((.not.(use_pmecore)).or.(use_pmecore).and.(rank.le.ndir-1))
     $   then
        call epreal0c
c
c     compute the Ewald self-energy term over all the atoms
c
        term = 2.0d0 * aewald * aewald
        fterm = -f * aewald / sqrtpi
        do ii = 1, npoleloc
           iipole = poleglob(ii)
           dix = rpole(2,iipole)
           diy = rpole(3,iipole)
           diz = rpole(4,iipole)
           uix = uind(1,iipole)
           uiy = uind(2,iipole)
           uiz = uind(3,iipole)
           uii = dix*uix + diy*uiy + diz*uiz
           e = fterm * term * uii / 3.0d0
           ep = ep + e
        end do
c
c       compute the cell dipole boundary correction term
c
        if (boundary .eq. 'VACUUM') then
           xd = 0.0d0
           yd = 0.0d0
           zd = 0.0d0
           xu = 0.0d0
           yu = 0.0d0
           zu = 0.0d0
           do ii = 1, npoleloc
              iipole = poleglob(ii)
              iglob = ipole(iipole)
              xd = xd + rpole(2,iipole) + rpole(1,iipole)*x(iglob)
              yd = yd + rpole(3,iipole) + rpole(1,iipole)*y(iglob)
              zd = zd + rpole(4,iipole) + rpole(1,iipole)*z(iglob)
              xu = xu + uind(1,iipole)
              yu = yu + uind(2,iipole)
              zu = zu + uind(3,iipole)
           end do
           term = (2.0d0/3.0d0) * f * (pi/volbox)
           ep = ep + term*(xd*xu+yd*yu+zd*zu)
        end if
      end if
      return
      end
c
c
c     #################################################################
c     ##                                                             ##
c     ##  subroutine epreal0c  --  real space polar energy via list  ##
c     ##                                                             ##
c     #################################################################
c
c
c     "epreal0c" calculates the induced dipole polarization energy
c     using particle mesh Ewald summation and a neighbor list
c
c
      subroutine epreal0c
      use sizes
      use atmlst
      use atoms
      use bound
      use chgpot
      use couple
      use domdec
      use energi
      use ewald
      use math
      use mpole
      use polar
      use polgrp
      use polpot
      use neigh
      use potent
      use shunt
      use mpi
      implicit none
      integer i,j,k,inl
      integer ii,kk,kkk,iipole,kkpole
      integer iglob,kglob,kbis
      real*8 e,f
      real*8 damp,expdamp
      real*8 erfc,bfac
      real*8 alsq2,alsq2n
      real*8 exp2a,ralpha
      real*8 pdi,pti,pgamma
      real*8 sc3,sc5,sc7
      real*8 psc3,psc5,psc7
      real*8 psr3,psr5,psr7
      real*8 xi,yi,zi
      real*8 xr,yr,zr
      real*8 r,r2,rr1
      real*8 rr3,rr5,rr7
      real*8 ci,dix,diy,diz
      real*8 qixx,qixy,qixz
      real*8 qiyy,qiyz,qizz
      real*8 uix,uiy,uiz
      real*8 ck,dkx,dky,dkz
      real*8 qkxx,qkxy,qkxz
      real*8 qkyy,qkyz,qkzz
      real*8 ukx,uky,ukz
      real*8 dri,drk,uri,urk
      real*8 qrix,qriy,qriz
      real*8 qrkx,qrky,qrkz
      real*8 qrri,qrrk
      real*8 duik,quik
      real*8 term1,term2,term3
      real*8 bn(0:3)
      real*8, allocatable :: pscale(:)
      character*6 mode
      external erfc
c
c
c     perform dynamic allocation of some local arrays
c
      allocate (pscale(n))
c
c     initialize connected atom exclusion coefficients
c
      pscale = 1.0d0
c
c     set conversion factor, cutoff and switching coefficients
c
      f = 0.5d0 * electric / dielec
      mode = 'MPOLE'
      call switch (mode)
c
c     compute the dipole polarization energy component
c
      do ii = 1, npolelocnl
         iipole = poleglobnl(ii)
         iglob = ipole(iipole)
         i = loc(iglob)
         pdi = pdamp(iipole)
         pti = thole(iipole)
         xi = x(iglob)
         yi = y(iglob)
         zi = z(iglob)
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
         uix = uind(1,iipole)
         uiy = uind(2,iipole)
         uiz = uind(3,iipole)
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
     &            pscale(i14(j,iglob)) = p4scale * p41scale
            end do
         end do
         do j = 1, n15(iglob)
            pscale(i15(j,iglob)) = p5scale
         end do
c
c     evaluate all sites within the cutoff distance
c
         do kkk = 1, nelst(ii)
            kkpole = elst(kkk,ii)
            kglob = ipole(kkpole)
            kbis = loc(kglob)
            xr = x(kglob) - xi
            yr = y(kglob) - yi
            zr = z(kglob) - zi
            if (use_bounds)  call image (xr,yr,zr)
            r2 = xr*xr + yr*yr + zr*zr
            if (r2 .le. off2) then
               r = sqrt(r2)
               ck = rpole(1,kkpole)
               dkx = rpole(2,kkpole)
               dky = rpole(3,kkpole)
               dkz = rpole(4,kkpole)
               qkxx = rpole(5,kkpole)
               qkxy = rpole(6,kkpole)
               qkxz = rpole(7,kkpole)
               qkyy = rpole(9,kkpole)
               qkyz = rpole(10,kkpole)
               qkzz = rpole(13,kkpole)
               ukx = uind(1,kkpole)
               uky = uind(2,kkpole)
               ukz = uind(3,kkpole)
c
c     get reciprocal distance terms for this interaction
c
               rr1 = f / r
               rr3 = rr1 / r2
               rr5 = 3.0d0 * rr3 / r2
               rr7 = 5.0d0 * rr5 / r2
c
c     calculate the real space Ewald error function terms
c
               ralpha = aewald * r
               bn(0) = erfc(ralpha) / r
               alsq2 = 2.0d0 * aewald**2
               alsq2n = 0.0d0
               if (aewald .gt. 0.0d0)  alsq2n = 1.0d0 / (sqrtpi*aewald)
               exp2a = exp(-ralpha**2)
               do j = 1, 3
                  bfac = dble(j+j-1)
                  alsq2n = alsq2 * alsq2n
                  bn(j) = (bfac*bn(j-1)+alsq2n*exp2a) / r2
               end do
               do j = 0, 3
                  bn(j) = f * bn(j)
               end do
c
c     apply Thole polarization damping to scale factors
c
               sc3 = 1.0d0
               sc5 = 1.0d0
               sc7 = 1.0d0
               damp = pdi * pdamp(kkpole)
               if (damp .ne. 0.0d0) then
                  pgamma = min(pti,thole(kkpole))
                  damp = -pgamma * (r/damp)**3
                  if (damp .gt. -50.0d0) then
                     expdamp = exp(damp)
                     sc3 = 1.0d0 - expdamp
                     sc5 = 1.0d0 - (1.0d0-damp)*expdamp
                     sc7 = 1.0d0 - (1.0d0-damp+0.6d0*damp**2)
     &                                    *expdamp
                  end if
               end if
c
c     intermediates involving Thole damping and scale factors
c
               psc3 = 1.0d0 - sc3*pscale(kglob)
               psc5 = 1.0d0 - sc5*pscale(kglob)
               psc7 = 1.0d0 - sc7*pscale(kglob)
               psr3 = bn(1) - psc3*rr3
               psr5 = bn(2) - psc5*rr5
               psr7 = bn(3) - psc7*rr7
c
c     intermediates involving moments and distance separation
c
               dri = dix*xr + diy*yr + diz*zr
               drk = dkx*xr + dky*yr + dkz*zr
               qrix = qixx*xr + qixy*yr + qixz*zr
               qriy = qixy*xr + qiyy*yr + qiyz*zr
               qriz = qixz*xr + qiyz*yr + qizz*zr
               qrkx = qkxx*xr + qkxy*yr + qkxz*zr
               qrky = qkxy*xr + qkyy*yr + qkyz*zr
               qrkz = qkxz*xr + qkyz*yr + qkzz*zr
               qrri = qrix*xr + qriy*yr + qriz*zr
               qrrk = qrkx*xr + qrky*yr + qrkz*zr
               uri = uix*xr + uiy*yr + uiz*zr
               urk = ukx*xr + uky*yr + ukz*zr
               duik = dix*ukx + diy*uky + diz*ukz
     &                   + dkx*uix + dky*uiy + dkz*uiz
               quik = qrix*ukx + qriy*uky + qriz*ukz
     &                   - qrkx*uix - qrky*uiy - qrkz*uiz
c
c     calculate intermediate terms for polarization interaction
c
               term1 = ck*uri - ci*urk + duik
               term2 = 2.0d0*quik - uri*drk - dri*urk
               term3 = uri*qrrk - urk*qrri
c
c     compute the energy contribution for this interaction
c
               e = term1*psr3 + term2*psr5 + term3*psr7
c
c     increment the overall polarization energy components
c
               ep = ep + e
            end if
         end do
c
c     reset exclusion coefficients for connected atoms
c
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
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (pscale)
      return
      end
c
c
c
c     ###################################################################
c     ##                                                               ##
c     ##  subroutine eprecip  --  PME recip space polarization energy  ##
c     ##                                                               ##
c     ###################################################################
c
c
c     "eprecip" evaluates the reciprocal space portion of particle
c     mesh Ewald summation energy due to dipole polarization
c
c     literature reference:
c
c     C. Sagui, L. G. Pedersen and T. A. Darden, "Towards an Accurate
c     Representation of Electrostatics in Classical Force Fields:
c     Efficient Implementation of Multipolar Interactions in
c     Biomolecular Simulations", Journal of Chemical Physics, 120,
c     73-87 (2004)
c
c     modifications for nonperiodic systems suggested by Tom Darden
c     during May 2007
c
c
      subroutine eprecip
      use atmlst
      use atoms
      use bound
      use boxes
      use chgpot
      use domdec
      use energi
      use ewald
      use fft
      use math
      use mpole
      use pme
      use polar
      use polpot
      use potent
      use mpi
      implicit none
      integer ierr,iipole,proc
      integer status(MPI_STATUS_SIZE),tag,commloc
      integer nprocloc,rankloc
      integer i,j,k,iglob
      integer k1,k2,k3
      integer m1,m2,m3
      integer ntot,nff
      integer nf1,nf2,nf3
      real*8 e,r1,r2,r3
      real*8 f,h1,h2,h3
      real*8 volterm,denom
      real*8 hsq,expterm
      real*8 term,pterm
      real*8 struc2
      real*8 a(3,3),ftc(10,10)
      real*8 fuind(3)
c
      if (use_pmecore) then
        nprocloc = nrec
        rankloc = rank_bis
        commloc =  comm_rec
      else
        nprocloc = nproc
        rankloc = rank
        commloc = MPI_COMM_WORLD
      end if
c
c     return if the Ewald coefficient is zero
c
      if (aewald .lt. 1.0d-6)  return
      f = electric / dielec
cc
cc     get the fractional to Cartesian transformation matrix
cc
      call frac_to_cart (ftc)
cc
cc     initialize variables required for the scalar summation
cc
c      pterm = (pi/aewald)**2
c      volterm = pi * volbox
c      nff = nfft1 * nfft2
c      nf1 = (nfft1+1) / 2
c      nf2 = (nfft2+1) / 2
c      nf3 = (nfft3+1) / 2
cc
cc     remove scalar sum virial from prior multipole 3-D FFT
cc
c      if (.not. use_mpole) then
c         call bspline_fill
c         call table_fill
cc
cc     assign only the permanent multipoles to the PME grid
cc     and perform the 3-D FFT forward transformation
cc
c         do i = 1, npole
c            cmp(1,i) = rpole(1,i)
c            cmp(2,i) = rpole(2,i)
c            cmp(3,i) = rpole(3,i)
c            cmp(4,i) = rpole(4,i)
c            cmp(5,i) = rpole(5,i)
c            cmp(6,i) = rpole(9,i)
c            cmp(7,i) = rpole(13,i)
c            cmp(8,i) = 2.0d0 * rpole(6,i)
c            cmp(9,i) = 2.0d0 * rpole(7,i)
c            cmp(10,i) = 2.0d0 * rpole(10,i)
c         end do
c         call cmp_to_fmp (cmp,fmp)
c         call grid_mpole (fmp)
c         call fftfront
cc
cc     make the scalar summation over reciprocal lattice
cc
c         do i = 1, ntot-1
c            k3 = i/nff + 1
c            j = i - (k3-1)*nff
c            k2 = j/nfft1 + 1
c            k1 = j - (k2-1)*nfft1 + 1
c            m1 = k1 - 1
c            m2 = k2 - 1
c            m3 = k3 - 1
c            if (k1 .gt. nf1)  m1 = m1 - nfft1
c            if (k2 .gt. nf2)  m2 = m2 - nfft2
c            if (k3 .gt. nf3)  m3 = m3 - nfft3
c            r1 = dble(m1)
c            r2 = dble(m2)
c            r3 = dble(m3)
c            h1 = recip(1,1)*r1 + recip(1,2)*r2 + recip(1,3)*r3
c            h2 = recip(2,1)*r1 + recip(2,2)*r2 + recip(2,3)*r3
c            h3 = recip(3,1)*r1 + recip(3,2)*r2 + recip(3,3)*r3
c            hsq = h1*h1 + h2*h2 + h3*h3
c            term = -pterm * hsq
c            expterm = 0.0d0
c            if (term .gt. -50.0d0) then
c               denom = volterm*hsq*bsmod1(k1)*bsmod2(k2)*bsmod3(k3)
c               expterm = exp(term) / denom
c               if (.not. use_bounds) then
c                  expterm = expterm * (1.0d0-cos(pi*xbox*sqrt(hsq)))
c               else if (octahedron) then
c                  if (mod(m1+m2+m3,2) .ne. 0)  expterm = 0.0d0
c               end if
c            end if
c            qfac(k1,k2,k3) = expterm
c         end do
cc
cc     account for zeroth grid point for nonperiodic system
cc
c         qfac(1,1,1) = 0.0d0
c         if (.not. use_bounds) then
c            expterm = 0.5d0 * pi / xbox
c            qfac(1,1,1) = expterm
c         end if
cc
cc     complete the transformation of the PME grid
cc
c         do k = 1, nfft3
c            do j = 1, nfft2
c               do i = 1, nfft1
c                  term = qfac(i,j,k)
c                  qgrid(1,i,j,k) = term * qgrid(1,i,j,k)
c                  qgrid(2,i,j,k) = term * qgrid(2,i,j,k)
c               end do
c            end do
c         end do
cc
cc     perform 3-D FFT backward transform and get potential
cc
c         call fftback
c         call fphi_mpole (fphi)
c      end if
c
c     convert Cartesian induced dipoles to fractional coordinates
c
      do i = 1, 3
         a(1,i) = dble(nfft1) * recip(i,1)
         a(2,i) = dble(nfft2) * recip(i,2)
         a(3,i) = dble(nfft3) * recip(i,3)
      end do
      e = 0d0
      do i = 1, npolerecloc
         iipole = polerecglob(i)
         iglob = ipole(iipole)
         fuind = 0d0
         do j = 1, 3
            fuind(j) = a(j,1)*uind(1,iipole) + a(j,2)*uind(2,iipole)
     &                      + a(j,3)*uind(3,iipole)
         end do
         do k = 1, 3
            e = e + fuind(k)*fphirec(k+1,i)
         end do
      end do
      e = 0.5d0 * electric*  e
      ep = ep + e
c
c     account for zeroth grid point for nonperiodic system
c
      if ((istart2(rankloc+1).eq.1).and.(jstart2(rankloc+1).eq.1)
     $   .and.(kstart2(rankloc+1).eq.1)) then
        if (.not. use_bounds) then
           expterm = 0.5d0 * pi / xbox
           struc2 = qgrid2in_2d(1,1,1,1,1)**2 +
     $       qgrid2in_2d(2,1,1,1,1)**2
           e = f * expterm * struc2
           ep = ep + e
        end if
      end if
c
      return
      end
