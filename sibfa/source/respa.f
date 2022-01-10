c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     #############################################################
c     ##                                                         ##
c     ##  subroutine respa  --  r-RESPA molecular dynamics step  ##
c     ##                                                         ##
c     #############################################################
c
c
c     "respa" performs a single multiple time step molecular dynamics
c     step using the reversible reference system propagation algorithm
c     (r-RESPA) via a Verlet core with the potential split into fast-
c     and slow-evolving portions
c
c     literature references:
c
c     D. D. Humphreys, R. A. Friesner and B. J. Berne, "A Multiple-
c     Time-Step Molecular Dynamics Algorithm for Macromolecules",
c     Journal of Physical Chemistry, 98, 6885-6892 (1994)
c
c     X. Qian and T. Schlick, "Efficient Multiple-Time-Step Integrators
c     with Distance-Based Force Splitting for Particle-Mesh-Ewald
c     Molecular Dynamics Simulations", Journal of Chemical Physics,
c     115, 4019-4029 (2001)
c
c
      subroutine respa(istep,dt)
      use atmtyp
      use atoms
      use cutoff
      use domdec
      use freeze
      use moldyn
      use timestat
      use units
      use usage
      use virial
      use mpi
      implicit none
      integer i,j,k,iglob
      integer istep
      integer nalt
      real*8 dt,dt_2
      real*8 dta,dta_2
      real*8 epot,etot
      real*8 eksum,eps
      real*8 temp,pres
      real*8 ealt,dalt
      real*8 ekin(3,3)
      real*8 stress(3,3)
      real*8 viralt(3,3)
      real*8 time0,time1
      real*8, allocatable :: derivs(:,:)
c
c
c     set some time values for the dynamics integration
c
      eps =  0.00000001d0
c      dalt = 0.00025d0
      dalt = 0.001d0
      nalt = int(dt/(dalt+eps)) + 1
      dalt = dble(nalt)
      dt_2 = 0.5d0 * dt
      dta = dt / dalt
      dta_2 = 0.5d0 * dta
cc
cc     make half-step temperature and pressure corrections
cc
c      call temper (dt)
c
c     store the current atom positions, then find half-step
c     velocities via velocity Verlet recursion
c
      do i = 1, nloc
         iglob = glob(i)
         if (use(iglob)) then
            do j = 1, 3
               v(j,iglob) = v(j,iglob) + a(j,iglob)*dt_2
            end do
         end if
      end do
c
c     initialize virial from fast-evolving potential energy terms
c
      do i = 1, 3
         do j = 1, 3
            viralt(j,i) = 0.0d0
         end do
      end do
c
c     find fast-evolving velocities and positions via Verlet recursion
c
      do k = 1, nalt
         do i = 1, nloc
            iglob = glob(i)
            if (use(iglob)) then
               do j = 1, 3
                  v(j,iglob) = v(j,iglob) + aalt(j,iglob)*dta_2
               end do
               xold(iglob) = x(iglob)
               yold(iglob) = y(iglob)
               zold(iglob) = z(iglob)
               x(iglob) = x(iglob) + v(1,iglob)*dta
               y(iglob) = y(iglob) + v(2,iglob)*dta
               z(iglob) = z(iglob) + v(3,iglob)*dta
            end if
         end do
         if (use_rattle)  call rattle (dta,xold,yold,zold)
c
c       Reassign the particules that have changed of domain
c
c       -> real space
c
        time0 = mpi_wtime()
c
        call reassignrespa(.true.,k,nalt)
c
        time1 = mpi_wtime()
        timereneig = timereneig + time1 - time0
c
c       communicate positions
c
        time0 = mpi_wtime()
        call commposrespa(k.ne.nalt)
        time1 = mpi_wtime()
        timecommstep = timecommstep + time1 - time0
c
        allocate (derivs(3,nbloc))
        derivs = 0d0
c
        time0 = mpi_wtime()
        call mechanicsteprespa(istep,.true.)
        time1 = mpi_wtime()
        timeparam = timeparam + time1 - time0
        time0 = mpi_wtime()
        call allocsteprespa(.true.)
        time1 = mpi_wtime()
        timeclear = timeclear + time1 - time0
c
c     get the fast-evolving potential energy and atomic forces
c
        call gradfast (ealt,derivs)
c
c       communicate forces
c
        call commforcesrespa(derivs,.true.)
c
c       MPI : get total energy
c
        call reduceen(ealt)
c
c     use Newton's second law to get fast-evolving accelerations;
c     update fast-evolving velocities using the Verlet recursion
c
          do i = 1, nloc
             iglob = glob(i)
             if (use(iglob)) then
                do j = 1, 3
                   aalt(j,iglob) = -convert *
     $                derivs(j,i) / mass(iglob)
                   v(j,iglob) = v(j,iglob) + aalt(j,iglob)*dta_2
                end do
             end if
          end do
        deallocate (derivs)
        if (use_rattle)  call rattle2 (dta)
c
c     increment average virial from fast-evolving potential terms
c
        do i = 1, 3
           do j = 1, 3
              viralt(j,i) = viralt(j,i) + vir(j,i)/dalt
           end do
        end do
      end do
c
c     Reassign the particules that have changed of domain
c
c     -> real space
c
      time0 = mpi_wtime()
c
      call reassignrespa(.false.,nalt,nalt)
c
c     -> reciprocal space
c
      call reassignpme(.false.)
      time1 = mpi_wtime()
      timereneig = timereneig + time1 - time0
c
c     communicate positions
c
      time0 = mpi_wtime()
      call commposrespa(.false.)
      call commposrec
      time1 = mpi_wtime()
      timecommstep = timecommstep + time1 - time0
c
c
      call reinitnl(istep)
c
      time0 = mpi_wtime()
      call mechanicsteprespa(istep,.false.)
      time1 = mpi_wtime()
      timeparam = timeparam + time1 - time0

      time0 = mpi_wtime()
      call allocsteprespa(.false.)
      time1 = mpi_wtime()
      timeclear = timeclear + time1 - time0
c
c     rebuild the neighbor lists
c
      if (use_list) call nblist(istep)
c
      allocate (derivs(3,nbloc))
      derivs = 0d0
c
c     get the slow-evolving potential energy and atomic forces
c
      call gradslow (epot,derivs)
c
c     if necessary, communicate some forces
c
      call commforcesrespa(derivs,.false.)
c
c     MPI : get total energy
c
      call reduceen(epot)
c
c     make half-step temperature and pressure corrections
c
      call temper2 (dt,temp)
c     call pressure2 (epot,temp)
c
c     use Newton's second law to get the slow accelerations;
c     find full-step velocities using velocity Verlet recursion
c
      do i = 1, nloc
         iglob = glob(i)
         if (use(iglob)) then
            do j = 1, 3
               a(j,iglob) = -convert * derivs(j,i) / mass(iglob)
               v(j,iglob) = v(j,iglob) + a(j,iglob)*dt_2
            end do
         end if
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (derivs)
c
c     find the constraint-corrected full-step velocities
c
      if (use_rattle)  call rattle2 (dt)
c
c     total potential and virial from sum of fast and slow parts
c
      epot = epot + ealt
      do i = 1, 3
         do j = 1, 3
            vir(j,i) = vir(j,i) + viralt(j,i)
         end do
      end do
c
c     make full-step temperature and pressure corrections
c
      call temper (dt,eksum,ekin,temp)
      call pressure (dt,epot,ekin,temp,pres,stress,istep)
c
c     total energy is sum of kinetic and potential energies
c
      etot = eksum + epot
c
c     compute statistics and save trajectory for this step
c
      call mdstat (istep,dt,etot,epot,eksum,temp,pres)
      call mdsave (istep,dt,epot)
      call mdrest (istep)
      return
      end
c
c
c
c     ##################################################################
c     ##                                                              ##
c     ##  subroutine gradfast  --  fast energy & gradient components  ##
c     ##                                                              ##
c     ##################################################################
c
c
c     "gradfast" calculates the potential energy and first derivatives
c     for the fast-evolving local valence potential energy terms
c
c
      subroutine gradfast (energy,derivs)
      use cutoff
      use potent
      implicit none
      real*8 energy
      real*8 derivs(3,*)
      logical save_vdw,save_charge
      logical save_dipole
      logical save_mpole,save_polar
      logical save_rxnfld,save_solv
      logical save_list
c
c
c     save the original state of slow-evolving potentials
c
      save_vdw = use_vdw
      save_charge = use_charge
      save_mpole = use_mpole
      save_polar = use_polar
      save_solv = use_solv
      save_list = use_list
c
c     turn off slow-evolving nonbonded potential energy terms
c
      use_vdw = .false.
      use_charge = .false.
      use_mpole = .false.
      use_polar = .false.
      use_solv = .false.
      use_list = .false.
c
c     get energy and gradient for fast-evolving potential terms
c
      call gradient (energy,derivs)
c
c     restore the original state of slow-evolving potentials
c
      use_vdw = save_vdw
      use_charge = save_charge
      use_mpole = save_mpole
      use_polar = save_polar
      use_solv = save_solv
      use_list = save_list
      return
      end
c
c
c     ##################################################################
c     ##                                                              ##
c     ##  subroutine gradslow  --  slow energy & gradient components  ##
c     ##                                                              ##
c     ##################################################################
c
c
c     "gradslow" calculates the potential energy and first derivatives
c     for the slow-evolving nonbonded potential energy terms
c
c
      subroutine gradslow (energy,derivs)
      use potent
      implicit none
      real*8 energy
      real*8 derivs(3,*)
      logical save_bond,save_angle
      logical save_strbnd,save_urey
      logical save_angang,save_opbend
      logical save_opdist,save_improp
      logical save_imptor,save_tors
      logical save_pitors,save_strtor
      logical save_tortor,save_geom
      logical save_metal,save_extra
c
c
c     save the original state of fast-evolving potentials
c
      save_bond = use_bond
      save_angle = use_angle
      save_strbnd = use_strbnd
      save_urey = use_urey
      save_angang = use_angang
      save_opbend = use_opbend
      save_opdist = use_opdist
      save_improp = use_improp
      save_imptor = use_imptor
      save_tors = use_tors
      save_pitors = use_pitors
      save_strtor = use_strtor
      save_tortor = use_tortor
      save_geom = use_geom
      save_extra = use_extra
c
c     turn off fast-evolving valence potential energy terms
c
      use_bond = .false.
      use_angle = .false.
      use_strbnd = .false.
      use_urey = .false.
      use_angang = .false.
      use_opbend = .false.
      use_opdist = .false.
      use_improp = .false.
      use_imptor = .false.
      use_tors = .false.
      use_pitors = .false.
      use_strtor = .false.
      use_tortor = .false.
      use_geom = .false.
      use_extra = .false.
c
c     get energy and gradient for slow-evolving potential terms
c
      call gradient (energy,derivs)
c
c     restore the original state of fast-evolving potentials
c
      use_bond = save_bond
      use_angle = save_angle
      use_strbnd = save_strbnd
      use_urey = save_urey
      use_angang = save_angang
      use_opbend = save_opbend
      use_opdist = save_opdist
      use_improp = save_improp
      use_imptor = save_imptor
      use_tors = save_tors
      use_pitors = save_pitors
      use_strtor = save_strtor
      use_tortor = save_tortor
      use_geom = save_geom
      use_extra = save_extra
      return
      end
c
