c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ################################################################
c     ##                                                            ##
c     ##  subroutine ehal1  --  buffered 14-7 energy & derivatives  ##
c     ##                                                            ##
c     ################################################################
c
c
c     "ehal1" calculates the buffered 14-7 van der Waals energy and
c     its first derivatives with respect to Cartesian coordinates
c
c
      subroutine ehal1
      use energi
      use virial
      use vdwpot
      implicit none
      real*8 elrc,vlrc
c
c
c     choose the method for summing over pairwise interactions
c
      call ehal1c
c
c     apply long range van der Waals correction if desired
c
      if (use_vcorr) then
         call evcorr1 (elrc,vlrc)
         ev = ev + elrc
         vir(1,1) = vir(1,1) + vlrc
         vir(2,2) = vir(2,2) + vlrc
         vir(3,3) = vir(3,3) + vlrc
      end if
      return
      end
c
c
c     ################################################################
c     ##                                                            ##
c     ##  subroutine ehal1c  --  buffered 14-7 vdw derivs via list  ##
c     ##                                                            ##
c     ################################################################
c
c
c     "ehal1c" calculates the buffered 14-7 van der Waals energy and
c     its first derivatives with respect to Cartesian coordinates
c     using a pairwise neighbor list
c
c
      subroutine ehal1c
      use atmlst
      use atoms
      use bound
      use couple
      use deriv
      use domdec
      use energi
      use group
      use inter
      use iounit
      use molcul
      use mutant
      use neigh
      use shunt
      use usage
      use virial
      use vdw
      use vdwpot
      implicit none
      integer i,j,k,iglob,kglob,kbis,idir,kdir,iivdw,inl
      integer ii,iv,it,ivloc
      integer kk,kv,kt,kvloc
      integer, allocatable :: iv14(:)
      real*8 e,de,eps,rdn
      real*8 fgrp,rv,rv7
      real*8 xi,yi,zi
      real*8 xr,yr,zr
      real*8 redi,rediv
      real*8 redk,redkv
      real*8 dedx,dedy,dedz
      real*8 rho,rho6,rho7
      real*8 tau,tau7,scal
      real*8 s1,s2,t1,t2
      real*8 dt1drho,dt2drho
      real*8 dtau,gtau
      real*8 taper,dtaper
      real*8 rik,rik2,rik3
      real*8 rik4,rik5
      real*8 rik6,rik7
      real*8 vxx,vyy,vzz
      real*8 vyx,vzx,vzy
      real*8 evt,eintert
      real*8 virt(3,3)
      real*8, allocatable :: xred(:)
      real*8, allocatable :: yred(:)
      real*8, allocatable :: zred(:)
      real*8, allocatable :: vscale(:)
      logical proceed,usei
      logical muti,mutk
      logical docompute
      character*6 mode
c
 1000 format(' Warning, system moved too much since last neighbor list'
     $   ' update, try lowering nlupdate VDW')
c
c
c     zero out the van der Waals energy and first derivatives
c
      ev = 0.0d0
c
c     perform dynamic allocation of some local arrays
c
      allocate (iv14(n))
      allocate (xred(nbloc))
      allocate (yred(nbloc))
      allocate (zred(nbloc))
      allocate (vscale(n))
c
c     set arrays needed to scale connected atom interactions
c
      vscale = 1.0d0
      iv14 = 0
c
c     set the coefficients for the switching function
c
      mode = 'VDW'
      call switch (mode)
c
c     apply any reduction factor to the atomic coordinates
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
c     find van der Waals energy and derivatives via neighbor list
c

      do ii = 1, nvdwlocnl
         iivdw = vdwglobnl(ii)
         iglob = ivdw(iivdw)
         i = loc(iglob)
         if ((i.eq.0).or.(i.gt.nbloc)) then
           write(iout,1000)
           cycle
         end if
         iv = ired(iglob)
         ivloc = loc(iv)
         redi = kred(iglob)
         rediv = 1.0d0 - redi
         it = jvdw(iglob)
         xi = xred(i)
         yi = yred(i)
         zi = zred(i)
         usei = (use(iglob) .or. use(iv))
         muti = mut(iglob)
c
c     set interaction scaling coefficients for connected atoms
c
         do j = 1, n12(iglob)
            vscale(i12(j,iglob)) = v2scale
         end do
         do j = 1, n13(iglob)
            vscale(i13(j,iglob)) = v3scale
         end do
         do j = 1, n14(iglob)
            vscale(i14(j,iglob)) = v4scale
            iv14(i14(j,iglob)) = iglob
         end do
         do j = 1, n15(iglob)
            vscale(i15(j,iglob)) = v5scale
         end do
c
c     decide whether to compute the current interaction
c
         do kk = 1, nvlst(ii)
            kglob = vlst(kk,ii)
            kbis = loc(kglob)
            kv = ired(kglob)
            kvloc = loc(kv)
            if ((kvloc.eq.0).or.(kbis.gt.nbloc).or.(kvloc.gt.nbloc)) 
     $          then
              write(iout,1000)
              cycle
            end if
            redk = kred(kglob)
            redkv = 1.0d0 - redk
            mutk = mut(kglob)
            proceed = .true.
            if (proceed)  proceed = (usei .or. use(kglob) .or. use(kv))
c
c     compute the energy contribution for this interaction
c
            if (proceed) then
               kt = jvdw(kglob)
               xr = xi - xred(kbis)
               yr = yi - yred(kbis)
               zr = zi - zred(kbis)
               if (use_bounds) call image (xr,yr,zr)
               rik2 = xr*xr + yr*yr + zr*zr
c
c     check for an interaction distance less than the cutoff
c
               if (rik2 .le. off2) then
                  rik = sqrt(rik2)
                  rv = radmin(kt,it)
                  eps = epsilon(kt,it)
                  if (iv14(kglob) .eq. iglob) then
                     rv = radmin4(kt,it)
                     eps = epsilon4(kt,it)
                  end if
                  eps = eps * vscale(kglob)
c
c     get the energy and gradient, via soft core if necessary
c
                  if ((muti .and. .not.mutk) .or.
     &                (mutk .and. .not.muti)) then
                     rho = rik / rv
                     rho6 = rho**6
                     rho7 = rho6 * rho
                     eps = eps * vlambda**scexp
                     scal = scalpha * (1.0d0-vlambda)**2
                     s1 = 1.0d0 / (scal+(rho+dhal)**7)
                     s2 = 1.0d0 / (scal+rho7+ghal)
                     t1 = (1.0d0+dhal)**7 * s1
                     t2 = (1.0d0+ghal) * s2
                     dt1drho = -7.0d0*(rho+dhal)**6 * t1 * s1
                     dt2drho = -7.0d0*rho6 * t2 * s2
                     e = eps * t1 * (t2-2.0d0)
                     de = eps * (dt1drho*(t2-2.0d0)+t1*dt2drho) / rv
                  else
                     rv7 = rv**7
                     rik6 = rik2**3
                     rik7 = rik6 * rik
                     rho = rik7 + ghal*rv7
                     tau = (dhal+1.0d0) / (rik + dhal*rv)
                     tau7 = tau**7
                     dtau = tau / (dhal+1.0d0)
                     gtau = eps*tau7*rik6*(ghal+1.0d0)*(rv7/rho)**2
                     e = eps*tau7*rv7*((ghal+1.0d0)*rv7/rho-2.0d0)
                     de = -7.0d0 * (dtau*e+gtau)
                  end if
c
c     use energy switching if near the cutoff distance
c
                  if (rik2 .gt. cut2) then
                     rik3 = rik2 * rik
                     rik4 = rik2 * rik2
                     rik5 = rik2 * rik3
                     taper = c5*rik5 + c4*rik4 + c3*rik3
     &                          + c2*rik2 + c1*rik + c0
                     dtaper = 5.0d0*c5*rik4 + 4.0d0*c4*rik3
     &                           + 3.0d0*c3*rik2 + 2.0d0*c2*rik + c1
                     de = e*dtaper + de*taper
                     e = e * taper
                  end if
c
c     scale the interaction based on its group membership
c
                  if (use_group) then
                     e = e * fgrp
                     de = de * fgrp
                  end if
c
c     find the chain rule terms for derivative components
c
                  de = de / rik
                  dedx = de * xr
                  dedy = de * yr
                  dedz = de * zr
c
c     increment the total van der Waals energy and derivatives
c
                  ev = ev + e
                  if (iglob .eq. iv) then
                    dev(1,i) = dev(1,i) + dedx
                    dev(2,i) = dev(2,i) + dedy
                    dev(3,i) = dev(3,i) + dedz
                  else
                    dev(1,i) = dev(1,i) + dedx*redi
                    dev(2,i) = dev(2,i) + dedy*redi
                    dev(3,i) = dev(3,i) + dedz*redi
c
                    dev(1,ivloc) = dev(1,ivloc) + dedx*rediv
                    dev(2,ivloc) = dev(2,ivloc) + dedy*rediv
                    dev(3,ivloc) = dev(3,ivloc) + dedz*rediv
                  end if
                  if (kglob .eq. kv) then
                    dev(1,kbis) = dev(1,kbis) - dedx
                    dev(2,kbis) = dev(2,kbis) - dedy
                    dev(3,kbis) = dev(3,kbis) - dedz
                  else
                    dev(1,kbis) = dev(1,kbis) - dedx*redk
                    dev(2,kbis) = dev(2,kbis) - dedy*redk
                    dev(3,kbis) = dev(3,kbis) - dedz*redk
c
                    dev(1,kvloc) = dev(1,kvloc) - dedx*redkv
                    dev(2,kvloc) = dev(2,kvloc) - dedy*redkv
                    dev(3,kvloc) = dev(3,kvloc) - dedz*redkv
                  end if
c
c     increment the internal virial tensor components
c
                  vxx = xr * dedx
                  vyx = yr * dedx
                  vzx = zr * dedx
                  vyy = yr * dedy
                  vzy = zr * dedy
                  vzz = zr * dedz
                  vir(1,1) = vir(1,1) + vxx
                  vir(2,1) = vir(2,1) + vyx
                  vir(3,1) = vir(3,1) + vzx
                  vir(1,2) = vir(1,2) + vyx
                  vir(2,2) = vir(2,2) + vyy
                  vir(3,2) = vir(3,2) + vzy
                  vir(1,3) = vir(1,3) + vzx
                  vir(2,3) = vir(2,3) + vzy
                  vir(3,3) = vir(3,3) + vzz
c
c     increment the total intermolecular energy
c
                  if (molcule(iglob) .ne. molcule(kglob)) then
                     einter = einter + e
                  end if
               end if
            end if
         end do
c
c     reset interaction scaling coefficients for connected atoms
c
         do j = 1, n12(iglob)
            vscale(i12(j,iglob)) = 1.0d0
         end do
         do j = 1, n13(iglob)
            vscale(i13(j,iglob)) = 1.0d0
         end do
         do j = 1, n14(iglob)
            vscale(i14(j,iglob)) = 1.0d0
         end do
         do j = 1, n15(iglob)
            vscale(i15(j,iglob)) = 1.0d0
         end do
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (iv14)
      deallocate (xred)
      deallocate (yred)
      deallocate (zred)
      deallocate (vscale)
      return
      end
