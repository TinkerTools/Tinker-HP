c
c
c     ##########################################################
c     ##  COPYRIGHT (C) 2020 by Chengwen Liu & Jay W. Ponder  ##
c     ##                 All Rights Reserved                  ##
c     ##########################################################
c
c     #############################################################
c     ##                                                         ##
c     ##  module cflux  --  charge flux terms in current system  ##
c     ##                                                         ##
c     #############################################################
c
c
c     nbflx   total number of bond charge flux interactions
c     naflx   total number of angle charge flux interactions
c     bflx    bond stretching charge flux constant (electrons/Ang)
c     winbflx window object corresponding to bflx
c     aflx    angle bending charge flux constant (electrons/radian)
c     winaflx window object corresponding to aflx
c     abflx   asymmetric stretch charge flux constant (electrons/Ang)
c     winabflx window object corresonding to abflx
c
c
#include "tinker_macro.h"
      module cflux
      implicit none
      integer nbflx
      integer naflx
      real(t_p), pointer :: bflx(:)
      real(t_p), pointer :: aflx(:,:)
      real(t_p), pointer :: abflx(:,:)
      integer winbflx,winaflx,winabflx

      interface
        module subroutine adflux1(dcf,de)
        real(r_p) dcf(*),de(*)
        end subroutine
        module subroutine adflux2(dcf,de)
        mdyn_rtyp dcf(*),de(*)
        end subroutine
      end interface

      interface
        module subroutine dcflux1 (pot,dcf)
        real(t_p) pot(*)
        real(r_p) dcf(*)
        end subroutine
        module subroutine dcflux2 (pot,dcf)
        real(t_p),intent(in   ):: pot(*)
        mdyn_rtyp,intent(inout):: dcf(*)
        end subroutine
      end interface

      end
