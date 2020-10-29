c
c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ###############################################################
c     ##                                                           ##
c     ##  subroutine elj1  --  Lennard-Jones energy & derivatives  ##
c     ##                                                           ##
c     ###############################################################
c
c
c     "elj1" calculates the Lennard-Jones 6-12 van der Waals energy
c     and its first derivatives with respect to Cartesian coordinates
c
c
#include "tinker_precision.h"
      module elj1gpu_inl
        contains
#include "image.f.inc"
#include "switch_respa.f.inc"
#include "pair_elj.f.inc"
      end module

      subroutine elj1gpu
      use energi
      use interfaces,only: elj1c_p,eljsl1c_p
      use potent
      use virial
      use vdwpot
      use utilgpu
      implicit none
      real(t_p) elrc,vlrc
c
c     choose the method for summing over pairwise interactions
c
      if (use_vdwshort.or.use_vdwlong) then
        call eljshortlong1cgpu
      else
        call elj1c_p
      end if
c
c     apply long range van der Waals correction if desired
c
      if (use_vcorr) then
         def_queue = dir_queue
!$acc data  create(elrc,vlrc) async(def_queue)
!$acc&      present(ev,vir)
         call evcorr1gpu (elrc,vlrc)
!$acc kernels async(def_queue)
         ev = ev + elrc
         vir(1,1) = vir(1,1) + vlrc
         vir(2,2) = vir(2,2) + vlrc
         vir(3,3) = vir(3,3) + vlrc
!$acc end kernels

!$acc end data
      end if
      end
c
c
c     ###############################################################
c     ##                                                           ##
c     ##  subroutine elj1c  --  Lennard-Jones vdw derivs via list  ##
c     ##                                                           ##
c     ###############################################################
c
c
c     "elj1c" calculates the Lennard-Jones 12-6 van der Waals energy
c     and its first derivatives using a pairwise neighbor list
c
c
      subroutine elj1cgpu
      use atmlst
      use atoms
      use bound
      use couple
      use deriv
      use domdec
      use elj1gpu_inl
      use energi
      use inform
      use inter
      use interfaces,only: elj1_scaling
      use iounit
      use molcul
      use neigh
      use shunt
      use tinMemory
      use tinTypes
      use usage
      use utilgpu
      use vdw
      use vdw_locArray
      use vdwpot
      use virial
      implicit none
      integer i,j,iglob,kglob,kbis,iivdw
      integer ii,iv,it,ivloc,kvloc
      integer kk,kv,kt
      integer, allocatable :: iv14(:)
      real(t_p) e,de,p6,p12,eps
      real(t_p) rv,rdn
      real(t_p) xi,yi,zi
      real(t_p) xr,yr,zr
      real(t_p) redi,rediv
      real(t_p) redk,redkv
      real(r_p) dedx,dedy,dedz
      real(t_p) rik,rik2,rik3
      real(t_p) rik4,rik5
      real(t_p) taper,dtaper
      type(real3) ded

      logical usei
      character*10 mode
c
 1000 format(' Warning, system moved too much since last neighbor list'
     $   ' update, try lowering nlupdate VDW')
      if (deb_Path) write(*,*) 'elj1cgpu'

      call prmem_request(xred,nvdwbloc,queue=dir_queue)
      call prmem_request(yred,nvdwbloc,queue=dir_queue)
      call prmem_request(zred,nvdwbloc,queue=dir_queue)
c
c     zero out the van der Waals energy and first derivatives
c
       ev = 0.0
c
c     set the coefficients for the switching function
c
      mode = 'VDW'
      call switch (mode)
!$acc data present(xred,yred,zred,vdwglob,ivdw,
!$acc&   loc,ired,kred,x,y,z,jvdw,vlst,nvlst,
!$acc&   ev,dev,g_vxx,g_vxy,g_vxz,g_vyy,g_vyz,g_vzz) async(dir_queue)
c
c     apply any reduction factor to the atomic coordinates
c
!$acc parallel loop async(dir_queue)
      do ii = 1, nvdwbloc
         iivdw   = vdwglob(ii)
         iglob   = ivdw(iivdw)
         i       = loc(iglob)
         iv      = ired(iglob)
         rdn     = kred(iglob)
         xred(i) = rdn*(x(iglob)-x(iv)) + x(iv)
         yred(i) = rdn*(y(iglob)-y(iv)) + y(iv)
         zred(i) = rdn*(z(iglob)-z(iv)) + z(iv)
      end do
c
c     find van der Waals energy and derivatives via neighbor list
c
!$acc parallel loop gang vector_length(32) async(dir_queue)
      do ii = 1, nvdwlocnl
         iivdw = vdwglobnl(ii)
         iglob = ivdw(iivdw)
         i     = loc(iglob)
         iv    = ired(iglob)
         ivloc = loc(iv)
         redi  = merge (kred(iglob),1.0_ti_p,(i.ne.ivloc))
         it    = jvdw(iglob)
         xi    = xred(i)
         yi    = yred(i)
         zi    = zred(i)
c        usei  = (use(iglob) .or. use(iv))
c
c     decide whether to compute the current interaction
c
!$acc loop vector
         do kk = 1, nvlst(ii)
            kglob = vlst(kk,ii)
            kbis  = loc(kglob)
            kv    = ired(kglob)
            kvloc = loc(kv)
            kt    = jvdw(kglob)
            xr    = xi - xred(kbis)
            yr    = yi - yred(kbis)
            zr    = zi - zred(kbis)
            if (use_bounds) call image_inl (xr,yr,zr)
            rik2  = xr*xr + yr*yr + zr*zr
c
c     check for an interaction distance less than the cutoff
c
            if (rik2.le.off2) then
               redk = merge (kred(kglob),1.0_ti_p,(kbis.ne.kvloc))
               rv   = radmin (kt,it)
               eps  = epsilon(kt,it)

               !compute the energy contribution for this interaction
               call elj1_couple(rik2,xr,yr,zr,rv,eps,cut2
     &                     ,cut,off,e,ded)
c
c     increment the total van der Waals energy and derivatives
c
               ev  = ev  + e

               dedx = ded%x*redi
               dedy = ded%y*redi
               dedz = ded%z*redi
!$acc atomic
               dev(1,i) = dev(1,i) + dedx
!$acc atomic
               dev(2,i) = dev(2,i) + dedy
!$acc atomic
               dev(3,i) = dev(3,i) + dedz
               if (iglob.ne.iv) then
                  dedx = ded%x*( 1.0-redi )
                  dedy = ded%y*( 1.0-redi )
                  dedz = ded%z*( 1.0-redi )
!$acc atomic
                  dev(1,ivloc) = dev(1,ivloc) + dedx
!$acc atomic
                  dev(2,ivloc) = dev(2,ivloc) + dedy
!$acc atomic
                  dev(3,ivloc) = dev(3,ivloc) + dedz
               end if

               dedx = ded%x*redk
               dedy = ded%y*redk
               dedz = ded%z*redk
!$acc atomic
               dev(1,kbis) = dev(1,kbis) - dedx
!$acc atomic
               dev(2,kbis) = dev(2,kbis) - dedy
!$acc atomic
               dev(3,kbis) = dev(3,kbis) - dedz
               if (kglob .ne. kv) then
                  dedx = ded%x*( 1.0-redk )
                  dedy = ded%y*( 1.0-redk )
                  dedz = ded%z*( 1.0-redk )
!$acc atomic
                  dev(1,kvloc) = dev(1,kvloc) - dedx
!$acc atomic
                  dev(2,kvloc) = dev(2,kvloc) - dedy
!$acc atomic
                  dev(3,kvloc) = dev(3,kvloc) - dedz
               end if
c
c     increment the internal virial tensor components
c
               g_vxx = g_vxx + xr * ded%x
               g_vxy = g_vxy + yr * ded%x
               g_vxz = g_vxz + zr * ded%x
               g_vyy = g_vyy + yr * ded%y
               g_vyz = g_vyz + zr * ded%y
               g_vzz = g_vzz + zr * ded%z
            end if
         end do
      end do

!$acc end data
      call elj1_scaling(xred,yred,zred
     &     ,g_vxx,g_vxy,g_vxz,g_vyy,g_vyz,g_vzz)

      end

#ifdef _CUDA
c=============================================================
c            CUDA Routine for Lennard-Jones 
c=============================================================
      subroutine elj1c_cu
      use atmlst    ,only: vdwglobnl,vdwglob
      use atoms     ,only: x,y,z,n
      use deriv     ,only: dev
      use domdec    ,only: loc,rank,nbloc,nproc
     &              ,xbegproc,xendproc,ybegproc,yendproc,zbegproc
     &              ,zendproc,glob
      use eljcu
      use energi    ,only: ev
      use inform    ,only: deb_Path
      use interfaces,only: elj1_scaling
      use neigh     ,only: cellv_glob,cellv_loc,cellv_jvdw
     &              ,vblst,ivblst
      use tinheader ,only: ti_p
      use timestat  ,only: timer_enter,timer_exit,timer_elj3
      use shunt     ,only: c0,c1,c2,c3,c4,c5,off2,off,cut2,cut
      use utilcu    ,only: check_launch_kernel
      use utilgpu   ,only: def_queue,dir_queue,rec_queue,dir_stream
     &              ,rec_stream,rec_event,stream_wait_async
     &              ,warp_size,def_stream,inf
     &              ,ered_buff,vred_buff,reduce_energy_virial
     &              ,zero_evir_red_buffer,prmem_request
      use vdw       ,only: ired,kred,jvdw,ivdw,radmin_c
     &              ,epsilon_c,nvdwbloc,nvdwlocnl
     &              ,nvdwlocnlb,nvdwclass
     &              ,nvdwlocnlb_pair,nvdwlocnlb2_pair
      use vdwpot    ,only: vcorrect_ik,vcorrect_scale,n_vscale,dhal,ghal
      use vdw_locArray
      use virial    ,only: vir,g_vxx,g_vxy,g_vxz,g_vyy,g_vyz,g_vzz
      implicit none
      integer i,k
      integer iglob,iivdw,iv,hal_Gs
      integer ierrSync,lst_start
#ifdef TINKER_DEBUG
      integer inter(n)
#endif
      real(t_p)  xbeg,xend,ybeg,yend,zbeg,zend
      real(t_p)  rdn,rdn1
      character*10 mode
c
      if(deb_Path) write (*,*) 'elj1c_cu'
      call timer_enter(timer_elj3)

      call prmem_request(xred    ,nvdwlocnlb,queue=def_queue)
      call prmem_request(yred    ,nvdwlocnlb,queue=def_queue)
      call prmem_request(zred    ,nvdwlocnlb,queue=def_queue)
      call prmem_request(xredc   ,nvdwbloc  ,queue=def_queue)
      call prmem_request(yredc   ,nvdwbloc  ,queue=def_queue)
      call prmem_request(zredc   ,nvdwbloc  ,queue=def_queue)
      call prmem_request(loc_ired,nvdwlocnlb,queue=def_queue)
      call prmem_request(loc_kred,nvdwlocnlb,queue=def_queue)

      def_queue = dir_queue
      def_stream = dir_stream
      xbeg = xbegproc(rank+1)
      xend = xendproc(rank+1)
      ybeg = ybegproc(rank+1)
      yend = yendproc(rank+1)
      zbeg = zbegproc(rank+1)
      zend = zendproc(rank+1)
      lst_start = 2*nvdwlocnlb_pair+1

#ifdef _OPENACC
      if (dir_queue.ne.rec_queue)
     &   call stream_wait_async(rec_stream,dir_stream,rec_event)
#endif

#ifdef TINKER_DEBUG
      inter(:) = 0
!$acc enter data copyin(inter)
#endif

c
c     apply any reduction factor to the atomic coordinates
c
!$acc parallel loop default(present) async(def_queue)
      do k = 1,nvdwlocnlb
         if (k.le.nvdwlocnl) then
            iglob    = cellv_glob(k)
            iv       = ired (iglob)
            rdn      = kred (iglob)
            rdn1     = 1.0_ti_p - rdn
            cellv_loc(k) = loc(iglob)
            loc_ired(k)  = loc(iv)
            if (iglob.eq.iv) then
               loc_kred(k) = rdn
            else
               loc_kred(k) = 1.0_ti_p
            end if
            xred(k)  = rdn * x(iglob) + rdn1 * x(iv)
            yred(k)  = rdn * y(iglob) + rdn1 * y(iv)
            zred(k)  = rdn * z(iglob) + rdn1 * z(iv)
         else
            ! Exclusion buffer to prevent interaction compute
            cellv_loc(k) = nbloc
            loc_ired(k)  = nbloc
            xred(k) = inf
            yred(k) = inf
            zred(k) = inf
         end if
      end do

!$acc parallel loop default(present) async(def_queue)
      do k = 1,nvdwbloc
         iglob     = ivdw(vdwglob(k))
         i         = loc  (iglob)
         iv        = ired (iglob)
         rdn       = kred (iglob)
         rdn1      = 1.0_ti_p - rdn
         xredc(i)  = rdn * x(iglob) + rdn1 * x(iv)
         yredc(i)  = rdn * y(iglob) + rdn1 * y(iv)
         zredc(i)  = rdn * z(iglob) + rdn1 * z(iv)
      end do

      call zero_evir_red_buffer(def_queue)
c
c     set the coefficients for the switching function
c
      mode = 'VDW'
      hal_Gs = nvdwlocnlb2_pair/8
      call switch (mode)

c
c     Call Lennard-Jones kernel in CUDA using C2 nblist
c
!$acc host_data use_device(xred,yred,zred,cellv_glob,cellv_loc
!$acc&    ,loc_ired,ivblst,vblst,cellv_jvdw,epsilon_c
!$acc&    ,radmin_c,ired,kred,dev,ered_buff,vred_buff
#ifdef TINKER_DEBUG
!$acc&    ,inter
#endif
!$acc&    )

      call elj1_cu<<<hal_Gs,4*warp_size,0,def_stream>>>
     &             (xred,yred,zred,cellv_glob,cellv_loc,loc_ired
     &             ,ivblst,vblst(lst_start),cellv_jvdw
     &             ,epsilon_c,radmin_c,ired,kred,dev
     &             ,ered_buff,vred_buff
     &             ,nvdwlocnlb2_pair,n,nbloc,nvdwlocnl,nvdwlocnlb
     &             ,nvdwclass
     &             ,c0,c1,c2,c3,c4,c5,cut2,cut,off2,off,ghal,dhal
     &             ,xbeg,xend,ybeg,yend,zbeg,zend
#ifdef TINKER_DEBUG
     &             ,inter,rank
#endif
     &             )
      call check_launch_kernel(" ehal1_cu2 ")

!$acc end host_data

      call reduce_energy_virial(ev,g_vxx,g_vxy,g_vxz,g_vyy,g_vyz,g_vzz
     &                         ,def_queue)

#ifdef TINKER_DEBUG
 34   format(2I10,3F12.4)
 36   format(A30,2I10)
 35   format(A30,I16,3x,F16.6,I16)
!$acc wait
!$acc exit data copyout(inter)
!$acc update host(dev,ev)
      write(*,36)'nvdw pair block ',nvdwlocnlb_pair,nvdwlocnlb2_pair
      write(*,35)'nev & ev & rank ',sum(inter),ev,rank
#endif

      call elj1_scaling(xredc,yredc,zredc,
     &            g_vxx,g_vxy,g_vxz,g_vyy,g_vyz,g_vzz)

      call timer_exit(timer_elj3)
      end subroutine
#endif
c
c
c     ####################################################################################
c     ##                                                                                ##
c     ##  subroutine eljshortlong1c  --  short range Lennard-Jones vdw derivs via list  ##
c     ##                                                                                ##
c     ####################################################################################
c
c
c     "eljshortlong1cgpu" calculates the short/long range Lennard-Jones 12-6 van der Waals energy
c     and its first derivatives using a pairwise neighbor list
c
c
      subroutine eljshortlong1cgpu
      use atmlst
      use atoms
      use bound
      use couple
      use cutoff
      use deriv
      use domdec
      use elj1gpu_inl
      use energi
      use inform
      use inter
      use interfaces, only:short_mode,long_mode
     &              , elj1shortlong_scaling
      use iounit
      use molcul
      use neigh
      use potent
      use shunt
      use tinMemory
      use usage
      use utilgpu
      use vdw
      use vdw_locArray
      use vdwpot
      use virial
      implicit none
      integer i,j,iglob,kglob,kbis,iivdw
      integer ii,iv,it,ivloc,kvloc
      integer kk,kv,kt
      integer range_cfg
      integer,pointer,save:: lst(:,:),nlst(:)

      real(t_p) e,de,p6,p12,eps,coff
      real(t_p) rv,rdn
      real(t_p) xi,yi,zi
      real(t_p) xr,yr,zr
      real(t_p) redi,rediv
      real(t_p) redk,redkv
      type(real3) ded
      real(r_p) dedx,dedy,dedz
      real(t_p) rik,rik2
      real(t_p) s,ds,vdwshortcut2

      logical usei
      character*10 mode
c
      if (deb_Path) write(*,*) "eljshortlong1cgpu"
c
c     zero out the van der Waals energy and first derivatives
c
      ev = 0.0
c
c     perform dynamic allocation of some local arrays
c
      call prmem_request(xred,nvdwbloc,queue=dir_queue)
      call prmem_request(yred,nvdwbloc,queue=dir_queue)
      call prmem_request(zred,nvdwbloc,queue=dir_queue)
c
c     set the coefficients for the switching function
c
      if (use_vdwshort) then
         mode = 'SHORTVDW'
         call switch (mode)
         vdwshortcut2 = 0
         coff = off
         range_cfg = short_mode
         lst  =>  shortvlst
         nlst => nshortvlst
      else
         mode = 'VDW'
         call switch (mode)
         vdwshortcut2 = (vdwshortcut-shortheal)**2
         range_cfg = long_mode
         coff = vdwshortcut
         lst  =>  vlst
         nlst => nvlst
      end if
!$acc data present(xred,yred,zred,vdwglob,ivdw,
!$acc&   loc,ired,kred,x,y,z,jvdw,vlst,nvlst,
!$acc&   ev,dev,g_vxx,g_vxy,g_vxz,g_vyy,g_vyz,g_vzz) async(dir_queue)
c
c     apply any reduction factor to the atomic coordinates
c
!$acc parallel loop async(dir_queue)
      do ii = 1, nvdwbloc
         iivdw   = vdwglob(ii)
         iglob   = ivdw(iivdw)
         i       = loc(iglob)
         iv      = ired(iglob)
         rdn     = kred(iglob)
         xred(i) = rdn*(x(iglob)-x(iv)) + x(iv)
         yred(i) = rdn*(y(iglob)-y(iv)) + y(iv)
         zred(i) = rdn*(z(iglob)-z(iv)) + z(iv)
      end do
c
c     find van der Waals energy and derivatives via neighbor list
c
!$acc parallel loop gang vector_length(32) async(dir_queue)
      do ii = 1, nvdwlocnl
         iivdw = vdwglobnl(ii)
         iglob = ivdw(iivdw)
         i     = loc(iglob)
         iv    = ired(iglob)
         ivloc = loc(iv)
         redi  = merge (kred(iglob),1.0_ti_p,(i.ne.ivloc))
         it    = jvdw(iglob)
         xi    = xred(i)
         yi    = yred(i)
         zi    = zred(i)
         usei  = (use(iglob) .or. use(iv))
c
c     decide whether to compute the current interaction
c
!$acc loop vector
         do kk = 1, nlst(ii)
            kglob = lst(kk,ii)
            kbis  = loc(kglob)
            kv    = ired(kglob)
            kvloc = loc(kv)
c
c     compute the energy contribution for this interaction
c
            kt    = jvdw(kglob)
            xr    = xi - xred(kbis)
            yr    = yi - yred(kbis)
            zr    = zi - zred(kbis)
            if (use_bounds) call image_inl (xr,yr,zr)
            rik2  = xr*xr + yr*yr + zr*zr
c
c     check for an interaction distance less than the cutoff
c
            if (rik2.le.off2 .and. rik2.ge.vdwshortcut2) then
               redk = merge (kred(kglob),1.0_ti_p,(kbis.ne.kvloc))
               rv   =  radmin(kt,it)
               eps  = epsilon(kt,it)

               call eljshortlong1_couple(rik2,xr,yr,zr,rv,eps
     &                 ,cut2,coff,shortheal,c0,c1,c2,c3,c4,c5
     &                 ,e,ded,range_cfg)
c
c     increment the total van der Waals energy and derivatives
c
               ev   = ev  + e
               !if (ii.eq.1) print*,e,kglob,rik2

               dedx = ded%x*redi
               dedy = ded%y*redi
               dedz = ded%z*redi
!$acc atomic
               dev(1,i) = dev(1,i) + dedx
!$acc atomic
               dev(2,i) = dev(2,i) + dedy
!$acc atomic
               dev(3,i) = dev(3,i) + dedz
               if (iglob.ne.iv) then
                  dedx = ded%x*( 1.0-redi )
                  dedy = ded%y*( 1.0-redi )
                  dedz = ded%z*( 1.0-redi )
!$acc atomic
                  dev(1,ivloc) = dev(1,ivloc) + dedx
!$acc atomic
                  dev(2,ivloc) = dev(2,ivloc) + dedy
!$acc atomic
                  dev(3,ivloc) = dev(3,ivloc) + dedz
               end if

               dedx = ded%x*redk
               dedy = ded%y*redk
               dedz = ded%z*redk
!$acc atomic
               dev(1,kbis) = dev(1,kbis) - dedx
!$acc atomic
               dev(2,kbis) = dev(2,kbis) - dedy
!$acc atomic
               dev(3,kbis) = dev(3,kbis) - dedz
               if (kglob .ne. kv) then
                  dedx = ded%x*( 1.0-redk )
                  dedy = ded%y*( 1.0-redk )
                  dedz = ded%z*( 1.0-redk )
!$acc atomic
                  dev(1,kvloc) = dev(1,kvloc) - dedx
!$acc atomic
                  dev(2,kvloc) = dev(2,kvloc) - dedy
!$acc atomic
                  dev(3,kvloc) = dev(3,kvloc) - dedz
               end if
c
c     increment the internal virial tensor components
c
               g_vxx = g_vxx + xr * dedx
               g_vxy = g_vxy + yr * dedx
               g_vxz = g_vxz + zr * dedx
               g_vyy = g_vyy + yr * dedy
               g_vyz = g_vyz + zr * dedy
               g_vzz = g_vzz + zr * dedz
            end if
         end do
      end do

!$acc end data

      call elj1shortlong_scaling(xred,yred,zred
     &     ,g_vxx,g_vxy,g_vxz,g_vyy,g_vyz,g_vzz)

      end
c
c     Scaling interaction correction subroutines for Lennard-Jones
c
      subroutine elj1_scaling(xred,yred,zred,
     &           vxx,vxy,vxz,vyy,vyz,vzz)

      use atmlst    ,only: vdwglobnl
      use deriv     ,only: dev
      use domdec    ,only: loc,rank
      use elj1gpu_inl
      use energi    ,only: ev
      use inform    ,only: deb_Path
      use tinheader ,only: ti_p
      use tintypes  ,only: real3
      use shunt     ,only: c0,c1,c2,c3,c4,c5,off2,off,cut2,cut
      use vdw       ,only: ired,kred,jvdw,ivdw,radmin,radmin4,
     &                     epsilon,epsilon4
      use vdwpot    ,only: vcorrect_ik,vcorrect_scale,n_vscale,dhal,ghal
      use utilgpu   ,only: dir_queue
      use virial
      implicit none
      integer i,j,k,kk,ksave
      integer kt,kglob,kbis,kvloc,kv,ki
      integer iglob,iivdw
      integer ii,iv,it,ivloc
      integer nnvlst,nnvlst2
      integer nn12,nn13,nn14,ntot
      integer interac
      real(t_p)  xi,yi,zi,redi,e,de
      real(t_p)  half,one
      real(t_p)  rdn,rdn1,redk
      real(t_p)  rik2
      type(real3) ded
      real(r_p)  devx,devy,devz
      real(t_p)  invrho,rv7orho
      real(t_p)  dtau,gtau,tau,tau7,rv7
      real(t_p)  rv2,eps2
      real(t_p)  xpos,ypos,zpos
      real(t_p)  vscale,vscale4
      logical    do_scale4
      character*10 mode

      real(t_p),intent(in):: xred(:)
      real(t_p),intent(in):: yred(:)
      real(t_p),intent(in):: zred(:)
      real(r_p)  vxx,vxy,vxz
      real(r_p)  vyy,vyz,vzz
      parameter(half=0.5_ti_p,
     &           one=1.0_ti_p)

      if (deb_Path) write(*,'(2x,a)') "elj1_scaling"

      ! Scaling factor correction loop
!$acc parallel loop async(dir_queue)
!$acc&     gang vector
!$acc&     present(xred,yred,zred,vxx,vxy,vxz,vyy,vyz,vzz)
!$acc&     present(loc,ired,kred,ivdw,loc,jvdw,vir,radmin,
!$acc&  radmin4,epsilon,epsilon4,vcorrect_ik,vcorrect_scale)
!$acc&     present(dev,ev)
      do ii = 1,n_vscale
         iglob  = vcorrect_ik(ii,1)
         kglob  = vcorrect_ik(ii,2)
         vscale = vcorrect_scale(ii)
         i      = loc(iglob)
         kbis   = loc(kglob)

         ivloc  = loc (ired(iglob))
         kvloc  = loc (ired(kglob))
         it     = jvdw(iglob)
         kt     = jvdw(kglob)

         redi   = merge (kred(iglob),1.0_ti_p,(i.ne.ivloc))
         redk   = merge (kred(kglob),1.0_ti_p,(kbis.ne.kvloc))

         do_scale4 = .false.
         vscale4   = 0

         if (vscale.lt.0) then 
            vscale4 = -vscale
            vscale = 1
         end if
c
c     compute the energy contribution for this interaction
c
         xpos   = xred(i) - xred(kbis)
         ypos   = yred(i) - yred(kbis)
         zpos   = zred(i) - zred(kbis)
         call image_inl(xpos,ypos,zpos)
c
c     decide whether to compute the current interaction
c     and check for an interaction distance less than the cutoff
c
         rik2   = xpos**2 + ypos**2 + zpos**2
         if (rik2>off2) cycle
c
c     replace 1-4 interactions
c
 20      continue
         if (do_scale4) then
            rv2  = radmin4 (kt,it)
            eps2 = epsilon4(kt,it)
         else
            rv2  =  radmin (kt,it)
            eps2 = epsilon (kt,it)
         end if

         call elj1_couple(rik2,xpos,ypos,zpos,rv2,eps2*vscale
     &                    ,cut2,cut,off,e,ded)

         if (.not.do_scale4) then
         e    = -e
         ded%x = -ded%x; ded%y = -ded%y; ded%z = -ded%z;
         end if

         ev   =   ev + e
         !if(rank.eq.0.and.mod(ii,1).eq.0) print*,iglob,kglob,vscale,e

         devx = redk*ded%x
         devy = redk*ded%y
         devz = redk*ded%z
!$acc atomic update
         dev(1,kbis)  = dev(1,kbis)  - devx
!$acc atomic update
         dev(2,kbis)  = dev(2,kbis)  - devy
!$acc atomic update
         dev(3,kbis)  = dev(3,kbis)  - devz

         if (kbis.ne.kvloc) then
            devx = (1.0_ti_p - redk)*ded%x
            devy = (1.0_ti_p - redk)*ded%y
            devz = (1.0_ti_p - redk)*ded%z
!$acc atomic update
            dev(1,kvloc) = dev(1,kvloc) - devx
!$acc atomic update
            dev(2,kvloc) = dev(2,kvloc) - devy
!$acc atomic update
            dev(3,kvloc) = dev(3,kvloc) - devz
         end if

         devx  = redi * ded%x
         devy  = redi * ded%y
         devz  = redi * ded%z
!$acc atomic update
         dev(1,i) = dev(1,i) + devx
!$acc atomic update
         dev(2,i) = dev(2,i) + devy
!$acc atomic update
         dev(3,i) = dev(3,i) + devz

         if (i.ne.ivloc) then
            devx  = (1.0_ti_p - redi)* ded%x
            devy  = (1.0_ti_p - redi)* ded%y
            devz  = (1.0_ti_p - redi)* ded%z
!$acc atomic update
            dev(1,ivloc) = dev(1,ivloc) + devx
!$acc atomic update
            dev(2,ivloc) = dev(2,ivloc) + devy
!$acc atomic update
            dev(3,ivloc) = dev(3,ivloc) + devz
         end if
c
c     increment the total van der Waals energy 
c
         vxx = vxx + xpos * ded%x
         vxy = vxy + ypos * ded%x
         vxz = vxz + zpos * ded%x
         vyy = vyy + ypos * ded%y
         vyz = vyz + zpos * ded%y
         vzz = vzz + zpos * ded%z

         ! deal with 1-4 Interactions
         if (vscale4.gt.0) then
            vscale    =  vscale4
            do_scale4 = .true.
            vscale4   = 0
            goto 20
         end if
      end do
      end subroutine

!
!     "elj1shortlong_scaling" for splited scaling interaction correction
!
      subroutine elj1shortlong_scaling(xred,yred,zred,
     &           vxx,vxy,vxz,vyy,vyz,vzz)

      use atmlst    ,only: vdwglobnl
      use cutoff    ,only: shortheal,vdwshortcut
      use deriv     ,only: dev
      use domdec    ,only: loc,rank
      use elj1gpu_inl
      use energi    ,only: ev
      use interfaces,only: long_mode,short_mode
      use inform    ,only: deb_Path
      use potent    ,only: use_vdwshort
      use tinheader ,only: ti_p
      use tintypes  ,only: real3
      use shunt     ,only: c0,c1,c2,c3,c4,c5,off2,off,cut2,cut
      use vdw       ,only: ired,kred,jvdw,ivdw,radmin,radmin4,
     &                     epsilon,epsilon4
      use vdwpot    ,only: vcorrect_ik,vcorrect_scale,n_vscale,dhal,ghal
      use utilgpu   ,only: dir_queue
      use virial
      implicit none
      integer i,j,k
      integer kt,kglob,kbis,kvloc,kv,ki
      integer iglob,iivdw
      integer ii,iv,it,ivloc
      integer range_cfg
      real(t_p)  redi,e,de
      real(t_p)  redk
      real(t_p)  rik2
      type(real3) ded
      real(r_p)  devx,devy,devz
      real(t_p)  rv2,eps2
      real(t_p)  xpos,ypos,zpos
      real(t_p)  vscale,vscale4
      real(t_p)  vdwshortcut2,coff
      logical    do_scale4
      character*10 mode

      real(t_p),intent(in):: xred(:)
      real(t_p),intent(in):: yred(:)
      real(t_p),intent(in):: zred(:)
      real(r_p)  vxx,vxy,vxz
      real(r_p)  vyy,vyz,vzz

      if (deb_Path) write(*,'(2x,a)') "elj1shortlong_scaling"

      if (use_vdwshort) then
         vdwshortcut2 = 0
         coff         = off
         range_cfg    = short_mode
      else
         vdwshortcut2 = (vdwshortcut-shortheal)**2
         coff         = vdwshortcut
         range_cfg    = long_mode
      end if

      ! Scaling factor correction loop
!$acc parallel loop async(dir_queue)
!$acc&     gang vector
!$acc&     present(xred,yred,zred,vxx,vxy,vxz,vyy,vyz,vzz)
!$acc&     present(loc,ired,kred,ivdw,loc,jvdw,vir,dev,radmin,
!$acc&  radmin4,epsilon,epsilon4,vcorrect_ik,vcorrect_scale)
!$acc&     present(ev)
      do ii = 1,n_vscale
         iglob  = vcorrect_ik(ii,1)
         kglob  = vcorrect_ik(ii,2)
         vscale = vcorrect_scale(ii)
         i      = loc(iglob)
         kbis   = loc(kglob)

         ivloc  = loc (ired(iglob))
         kvloc  = loc (ired(kglob))
         it     = jvdw(iglob)
         kt     = jvdw(kglob)

         redi   = merge (kred(iglob),1.0_ti_p,(i.ne.ivloc))
         redk   = merge (kred(kglob),1.0_ti_p,(kbis.ne.kvloc))

         do_scale4 = .false.
         vscale4   = 0

         if (vscale.lt.0) then 
            vscale4 = -vscale
            vscale = 1
         end if
c
c     compute the energy contribution for this interaction
c
         xpos   = xred(i) - xred(kbis)
         ypos   = yred(i) - yred(kbis)
         zpos   = zred(i) - zred(kbis)
         call image_inl(xpos,ypos,zpos)
c
c     decide whether to compute the current interaction
c     and check for an interaction distance less than the cutoff
c
         rik2   = xpos**2 + ypos**2 + zpos**2
         if (rik2<vdwshortcut2.or.rik2>off2) cycle
c
c     replace 1-4 interactions
c
 20      continue
         if (do_scale4) then
            rv2  = radmin4 (kt,it)
            eps2 = epsilon4(kt,it)
         else
            rv2  =  radmin (kt,it)
            eps2 = epsilon (kt,it)
         end if

         call eljshortlong1_couple(rik2,xpos,ypos,zpos,rv2,eps2*vscale
     &           ,cut2,coff,shortheal,c0,c1,c2,c3,c4,c5
     &           ,e,ded,range_cfg)

         if (.not.do_scale4) then
         e    = -e
         ded%x = -ded%x; ded%y = -ded%y; ded%z = -ded%z;
         end if

         ev   =   ev + e
         !if(rank.eq.0.and.mod(ii,1).eq.0) print*,iglob,kglob,rik2,e

         devx = redk*ded%x
         devy = redk*ded%y
         devz = redk*ded%z
!$acc atomic update
         dev(1,kbis)  = dev(1,kbis)  - devx
!$acc atomic update
         dev(2,kbis)  = dev(2,kbis)  - devy
!$acc atomic update
         dev(3,kbis)  = dev(3,kbis)  - devz

         if (kbis.ne.kvloc) then
            devx = (1.0_ti_p - redk)*ded%x
            devy = (1.0_ti_p - redk)*ded%y
            devz = (1.0_ti_p - redk)*ded%z
!$acc atomic update
            dev(1,kvloc) = dev(1,kvloc) - devx
!$acc atomic update
            dev(2,kvloc) = dev(2,kvloc) - devy
!$acc atomic update
            dev(3,kvloc) = dev(3,kvloc) - devz
         end if

         devx  = redi * ded%x
         devy  = redi * ded%y
         devz  = redi * ded%z
!$acc atomic update
         dev(1,i) = dev(1,i) + devx
!$acc atomic update
         dev(2,i) = dev(2,i) + devy
!$acc atomic update
         dev(3,i) = dev(3,i) + devz

         if (i.ne.ivloc) then
            devx  = (1.0_ti_p - redi)* ded%x
            devy  = (1.0_ti_p - redi)* ded%y
            devz  = (1.0_ti_p - redi)* ded%z
!$acc atomic update
            dev(1,ivloc) = dev(1,ivloc) + devx
!$acc atomic update
            dev(2,ivloc) = dev(2,ivloc) + devy
!$acc atomic update
            dev(3,ivloc) = dev(3,ivloc) + devz
         end if
c
c     increment the total van der Waals energy 
c
         vxx = vxx + xpos * ded%x
         vxy = vxy + ypos * ded%x
         vxz = vxz + zpos * ded%x
         vyy = vyy + ypos * ded%y
         vyz = vyz + zpos * ded%y
         vzz = vzz + zpos * ded%z

         ! deal with 1-4 Interactions
         if (vscale4.gt.0) then
            vscale    =  vscale4
            do_scale4 = .true.
            vscale4   = 0
            goto 20
         end if
      end do
      end subroutine