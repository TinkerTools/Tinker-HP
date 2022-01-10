c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ###############################################################
c     ##                                                           ##
c     ##  subroutine readprm  --  input of force field parameters  ##
c     ##                                                           ##
c     ###############################################################
c
c
c     "readprm" processes the potential energy parameter file
c     in order to define the default force field parameters
c
c
      subroutine readprm
      use dispersion
      use fields
      use iounit
      use kanang
      use kangs
      use katoms
      use kbonds
      use kchrge
      use kct
      use kiprop
      use kitors
      use khbond
      use kmulti
      use kopbnd
      use kopdst
      use kpitor
      use kpolr
      use kstbnd
      use ksttor
      use ktorsn
      use ktrtor
      use kurybr
      use kvdwpr
      use kvdws
      use merck
      use mpole
      use params
      use repulsion
      implicit none
      integer i,j,iprm
      integer ia,ib,ic,id,ie
      integer if,ig,ih,ii
      integer size,next
      integer length,trimtext
      integer nb,nb5,nb4,nb3,nel
      integer na,na5,na4,na3,naf
      integer nsb,nu,nopb,nopd
      integer ndi,nti,nt,nt5,nt4
      integer npt,nbt,ntt,nd,nd5
      integer nd4,nd3,nvp,nhb,nmp
      integer npi,npi5,npi4
      integer cls,atn,lig
      integer nx,ny,nxy
      integer bt,at,sbt,tt
      integer ft(6),pg(maxvalue)
      real*8 wght,rd,ep,rdn
      real*8 an1,an2,an3
      real*8 ba1,ba2
      real*8 aa1,aa2,aa3
      real*8 bt1,bt2,bt3
      real*8 an,pr,ds,dk
      real*8 vd,cg,dp,ps
      real*8 fc,bd,dl,el
      real*8 pt,pol,thl
      real*8 iz,rp,ss,ts
      real*8 abc,cba
      real*8 gi,alphi
      real*8 nni,factor
      real*8 vt(6),st(6)
      real*8 pl(13)
      real*8 emtp1,emtp2,emtp3,emtp4
      real*8 tx(maxtgrd2)
      real*8 ty(maxtgrd2)
      real*8 tf(maxtgrd2)
      real*8 hybrid1,hybrid2,tas1,tas2,tas3,tas4,tas5
      real*8 vdw1,vdw2,vdw3,tap1,tap2,tap3,tap4,tap5
      real*8 ma1,ma2,ma3,ma4,ma5
      real*8 ialp1,ialp2,orb
      real*8 aion,aelec
      real*8 crep11,crep12,crep21,crep22,crep31,crep32
      real*8 exporep1,exporep2
      real*8 c6disp1,c8disp1,c10disp1
      real*8 scdp1,facdispij1,discof1,colpa1,colp1,bdmp1
      real*8 admp61,admp81,admp101,cxd1,axd1,cxdla1,axdla1
      real*8 cxdlp1,axdlp1
      logical header
      character*1 da1
      character*4 pa,pb,pc
      character*4 pd,pe
      character*8 axt
      character*20 keyword
      character*120 record
      character*120 string
c
c
c     initialize the counters for some parameter types
c
      nvp = 0
      nhb = 0
      nb = 0
      nb5 = 0
      nb4 = 0
      nb3 = 0
      nel = 0
      na = 0
      na5 = 0
      na4 = 0
      na3 = 0
      naf = 0
      nsb = 0
      nu = 0
      nopb = 0
      nopd = 0
      ndi = 0
      nti = 0
      nt = 0
      nt5 = 0
      nt4 = 0
      npt = 0
      nbt = 0
      ntt = 0
      nd = 0
      nd5 = 0
      nd4 = 0
      nd3 = 0
      nmp = 0
      npi = 0
      npi5 = 0
      npi4 = 0
c
c     number of characters in an atom number text string
c
      size = 4
c
c     set blank line header before echoed comment lines
c
      header = .true.
c
c     process each line of the parameter file, first
c     extract the keyword at the start of each line
c
      iprm = 0
      dowhile (iprm .lt. nprm)
         iprm = iprm + 1
         record = prmline(iprm)
         next = 1
         call gettext (record,keyword,next)
         call upcase (keyword)
c
c     check for a force field modification keyword
c
         call prmkey (record)
c
c     comment line to be echoed to the output
c
         if (keyword(1:5) .eq. 'ECHO ') then
            string = record(next:120)
            length = trimtext (string)
            if (header) then
               header = .false.
               write (iout,10)
   10          format ()
            end if
            if (length .eq. 0) then
               write (iout,20)
   20          format ()
            else
               write (iout,30)  string(1:length)
   30          format (a)
            end if
c
c     atom type definitions and parameters
c
         else if (keyword(1:5) .eq. 'ATOM ') then
            ia = 0
            cls = 0
            atn = 0
            wght = 0.0d0
            lig = 0
            call getnumb (record,ia,next)
            call getnumb (record,cls,next)
            if (cls .eq. 0)  cls = ia
            atmcls(ia) = cls
            if (ia .ge. maxtyp) then
               write (iout,40)
   40          format (/,' READPRM  --  Too many Atom Types;',
     &                    ' Increase MAXTYP')
               call fatal
            else if (cls .ge. maxclass) then
               write (iout,50)
   50          format (/,' READPRM  --  Too many Atom Classes;',
     &                    ' Increase MAXCLASS')
               call fatal
            end if
            if (ia .ne. 0) then
               call gettext (record,symbol(ia),next)
               call getstring (record,describe(ia),next)
               string = record(next:120)
               read (string,*,err=60,end=60)  atn,wght,lig
   60          continue
               atmnum(ia) = atn
               weight(ia) = wght
               ligand(ia) = lig
            end if
c
c     van der Waals parameters for individual atom types
c
         else if (keyword(1:4) .eq. 'VDW ') then
            ia = 0
            rd = 0.0d0
            ep = 0.0d0
            rdn = 0.0d0
            string = record(next:120)
            read (string,*,err=70,end=70)  ia,rd,ep,rdn
   70       continue
            if (ia .ne. 0) then
               rad(ia) = rd
               eps(ia) = ep
               reduct(ia) = rdn
            end if
c
c     van der Waals 1-4 parameters for individual atom types
c
         else if (keyword(1:6) .eq. 'VDW14 ') then
            ia = 0
            rd = 0.0d0
            ep = 0.0d0
            string = record(next:120)
            read (string,*,err=80,end=80)  ia,rd,ep
   80       continue
            if (ia .ne. 0) then
               rad4(ia) = rd
               eps4(ia) = ep
            end if
c
c     van der Waals parameters for specific atom pairs
c
         else if (keyword(1:6) .eq. 'VDWPR ') then
            ia = 0
            ib = 0
            rd = 0.0d0
            ep = 0.0d0
            string = record(next:120)
            read (string,*,err=90,end=90)  ia,ib,rd,ep
   90       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            nvp = nvp + 1
            if (ia .le. ib) then
               kvpr(nvp) = pa//pb
            else
               kvpr(nvp) = pb//pa
            end if
            radpr(nvp) = rd
            epspr(nvp) = ep
c
c     van der Waals parameters for hydrogen bonding pairs
c
         else if (keyword(1:6) .eq. 'HBOND ') then
            ia = 0
            ib = 0
            rd = 0.0d0
            ep = 0.0d0
            string = record(next:120)
            read (string,*,err=100,end=100)  ia,ib,rd,ep
  100       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            nhb = nhb + 1
            if (ia .le. ib) then
               khb(nhb) = pa//pb
            else
               khb(nhb) = pb//pa
            end if
            radhb(nhb) = rd
            epshb(nhb) = ep
c
c     bond stretching parameters
c
         else if (keyword(1:5) .eq. 'BOND ') then
            ia = 0
            ib = 0
            fc = 0.0d0
            bd = 0.0d0
            string = record(next:120)
            read (string,*,err=110,end=110)  ia,ib,fc,bd
  110       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            nb = nb + 1
            if (ia .le. ib) then
               kb(nb) = pa//pb
            else
               kb(nb) = pb//pa
            end if
            bcon(nb) = fc
            blen(nb) = bd
c
c     bond stretching parameters for 5-membered rings
c
         else if (keyword(1:6) .eq. 'BOND5 ') then
            ia = 0
            ib = 0
            fc = 0.0d0
            bd = 0.0d0
            string = record(next:120)
            read (string,*,err=120,end=120)  ia,ib,fc,bd
  120       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            nb5 = nb5 + 1
            if (ia .le. ib) then
               kb5(nb5) = pa//pb
            else
               kb5(nb5) = pb//pa
            end if
            bcon5(nb5) = fc
            blen5(nb5) = bd
c
c     bond stretching parameters for 4-membered rings
c
         else if (keyword(1:6) .eq. 'BOND4 ') then
            ia = 0
            ib = 0
            fc = 0.0d0
            bd = 0.0d0
            string = record(next:120)
            read (string,*,err=130,end=130)  ia,ib,fc,bd
  130       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            nb4 = nb4 + 1
            if (ia .le. ib) then
               kb4(nb4) = pa//pb
            else
               kb4(nb4) = pb//pa
            end if
            bcon4(nb4) = fc
            blen4(nb4) = bd
c
c     bond stretching parameters for 3-membered rings
c
         else if (keyword(1:6) .eq. 'BOND3 ') then
            ia = 0
            ib = 0
            fc = 0.0d0
            bd = 0.0d0
            string = record(next:120)
            read (string,*,err=140,end=140)  ia,ib,fc,bd
  140       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            nb3 = nb3 + 1
            if (ia .le. ib) then
               kb3(nb3) = pa//pb
            else
               kb3(nb3) = pb//pa
            end if
            bcon3(nb3) = fc
            blen3(nb3) = bd
c
c     electronegativity bond length correction parameters
c
         else if (keyword(1:9) .eq. 'ELECTNEG ') then
            ia = 0
            ib = 0
            ic = 0
            dl = 0.0d0
            string = record(next:120)
            read (string,*,err=150,end=150)  ia,ib,ic,dl
  150       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            nel = nel + 1
            if (ia .le. ic) then
               kel(nel) = pa//pb//pc
            else
               kel(nel) = pc//pb//pa
            end if
            dlen(nel) = dl
c
c     bond angle bending parameters
c
         else if (keyword(1:6) .eq. 'ANGLE ') then
            ia = 0
            ib = 0
            ic = 0
            fc = 0.0d0
            an1 = 0.0d0
            an2 = 0.0d0
            an3 = 0.0d0
            string = record(next:120)
            read (string,*,err=160,end=160)  ia,ib,ic,fc,an1,an2,an3
  160       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            na = na + 1
            if (ia .le. ic) then
               ka(na) = pa//pb//pc
            else
               ka(na) = pc//pb//pa
            end if
            acon(na) = fc
            ang(1,na) = an1
            ang(2,na) = an2
            ang(3,na) = an3
c
c     angle bending parameters for 5-membered rings
c
         else if (keyword(1:7) .eq. 'ANGLE5 ') then
            ia = 0
            ib = 0
            ic = 0
            fc = 0.0d0
            an1 = 0.0d0
            an2 = 0.0d0
            an3 = 0.0d0
            string = record(next:120)
            read (string,*,err=170,end=170)  ia,ib,ic,fc,an1,an2,an3
  170       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            na5 = na5 + 1
            if (ia .le. ic) then
               ka5(na5) = pa//pb//pc
            else
               ka5(na5) = pc//pb//pa
            end if
            acon5(na5) = fc
            ang5(1,na5) = an1
            ang5(2,na5) = an2
            ang5(3,na5) = an3
c
c     angle bending parameters for 4-membered rings
c
         else if (keyword(1:7) .eq. 'ANGLE4 ') then
            ia = 0
            ib = 0
            ic = 0
            fc = 0.0d0
            an1 = 0.0d0
            an2 = 0.0d0
            an3 = 0.0d0
            string = record(next:120)
            read (string,*,err=180,end=180)  ia,ib,ic,fc,an1,an2,an3
  180       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            na4 = na4 + 1
            if (ia .le. ic) then
               ka4(na4) = pa//pb//pc
            else
               ka4(na4) = pc//pb//pa
            end if
            acon4(na4) = fc
            ang4(1,na4) = an1
            ang4(2,na4) = an2
            ang4(3,na4) = an3
c
c     angle bending parameters for 3-membered rings
c
         else if (keyword(1:7) .eq. 'ANGLE3 ') then
            ia = 0
            ib = 0
            ic = 0
            fc = 0.0d0
            an1 = 0.0d0
            an2 = 0.0d0
            an3 = 0.0d0
            string = record(next:120)
            read (string,*,err=190,end=190)  ia,ib,ic,fc,an1,an2,an3
  190       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            na3 = na3 + 1
            if (ia .le. ic) then
               ka3(na3) = pa//pb//pc
            else
               ka3(na3) = pc//pb//pa
            end if
            acon3(na3) = fc
            ang3(1,na3) = an1
            ang3(2,na3) = an2
            ang3(3,na3) = an3
c
c     Fourier bond angle bending parameters
c
         else if (keyword(1:7) .eq. 'ANGLEF ') then
            ia = 0
            ib = 0
            ic = 0
            fc = 0.0d0
            an = 0.0d0
            pr = 0.0d0
            string = record(next:120)
            read (string,*,err=200,end=200)  ia,ib,ic,fc,an,pr
  200       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            naf = naf + 1
            if (ia .le. ic) then
               kaf(naf) = pa//pb//pc
            else
               kaf(naf) = pc//pb//pa
            end if
            aconf(naf) = fc
            angf(1,naf) = an
            angf(2,naf) = pr
c
c     stretch-bend parameters
c
         else if (keyword(1:7) .eq. 'STRBND ') then
            ia = 0
            ib = 0
            ic = 0
            ba1 = 0.0d0
            ba2 = 0.0d0
            string = record(next:120)
            read (string,*,err=210,end=210)  ia,ib,ic,ba1,ba2
  210       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            nsb = nsb + 1
            if (ia .le. ic) then
               ksb(nsb) = pa//pb//pc
               stbn(1,nsb) = ba1
               stbn(2,nsb) = ba2
            else
               ksb(nsb) = pc//pb//pa
               stbn(1,nsb) = ba2
               stbn(2,nsb) = ba1
            end if
c
c     Urey-Bradley parameters
c
         else if (keyword(1:9) .eq. 'UREYBRAD ') then
            ia = 0
            ib = 0
            ic = 0
            fc = 0.0d0
            ds = 0.0d0
            string = record(next:120)
            read (string,*,err=220,end=220)  ia,ib,ic,fc,ds
  220       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            nu = nu + 1
            if (ia .le. ic) then
               ku(nu) = pa//pb//pc
            else
               ku(nu) = pc//pb//pa
            end if
            ucon(nu) = fc
            dst13(nu) = ds
c
c     angle-angle parameters
c
         else if (keyword(1:7) .eq. 'ANGANG ') then
            ia = 0
            aa1 = 0.0d0
            aa2 = 0.0d0
            aa3 = 0.0d0
            string = record(next:120)
            read (string,*,err=230,end=230)  ia,aa1,aa2,aa3
  230       continue
            if (ia .ne. 0) then
               anan(1,ia) = aa1
               anan(2,ia) = aa2
               anan(3,ia) = aa3
            end if
c
c     out-of-plane bend parameters
c
         else if (keyword(1:7) .eq. 'OPBEND ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            fc = 0.0d0
            string = record(next:120)
            read (string,*,err=240,end=240)  ia,ib,ic,id,fc
  240       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nopb = nopb + 1
            kopb(nopb) = pa//pb//pc//pd
            opbn(nopb) = fc
c
c     out-of-plane distance parameters
c
         else if (keyword(1:7) .eq. 'OPDIST ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            fc = 0.0d0
            string = record(next:120)
            read (string,*,err=250,end=250)  ia,ib,ic,id,fc
  250       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nopd = nopd + 1
            kopd(nopd) = pa//pb//pc//pd
            opds(nopd) = fc
c
c     improper dihedral parameters
c
         else if (keyword(1:9) .eq. 'IMPROPER ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            dk = 0.0d0
            vd = 0.0d0
            string = record(next:120)
            read (string,*,err=260,end=260)  ia,ib,ic,id,dk,vd
  260       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            ndi = ndi + 1
            kdi(ndi) = pa//pb//pc//pd
            dcon(ndi) = dk
            tdi(ndi) = vd
c
c     improper torsional parameters
c
         else if (keyword(1:8) .eq. 'IMPTORS ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            do i = 1, 6
               vt(i) = 0.0d0
               st(i) = 0.0d0
               ft(i) = 0
            end do
            string = record(next:120)
            read (string,*,err=270,end=270)  ia,ib,ic,id,
     &                                       (vt(j),st(j),ft(j),j=1,6)
  270       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nti = nti + 1
            kti(nti) = pa//pb//pc//pd
            call torphase (ft,vt,st)
            ti1(1,nti) = vt(1)
            ti1(2,nti) = st(1)
            ti2(1,nti) = vt(2)
            ti2(2,nti) = st(2)
            ti3(1,nti) = vt(3)
            ti3(2,nti) = st(3)
c
c     torsional parameters
c
         else if (keyword(1:8) .eq. 'TORSION ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            do i = 1, 6
               vt(i) = 0.0d0
               st(i) = 0.0d0
               ft(i) = 0
            end do
            string = record(next:120)
            read (string,*,err=280,end=280)  ia,ib,ic,id,
     &                                       (vt(j),st(j),ft(j),j=1,6)
  280       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nt = nt + 1
            if (ib .lt. ic) then
               kt(nt) = pa//pb//pc//pd
            else if (ic .lt. ib) then
               kt(nt) = pd//pc//pb//pa
            else if (ia .le. id) then
               kt(nt) = pa//pb//pc//pd
            else if (id .lt. ia) then
               kt(nt) = pd//pc//pb//pa
            end if
            call torphase (ft,vt,st)
            t1(1,nt) = vt(1)
            t1(2,nt) = st(1)
            t2(1,nt) = vt(2)
            t2(2,nt) = st(2)
            t3(1,nt) = vt(3)
            t3(2,nt) = st(3)
            t4(1,nt) = vt(4)
            t4(2,nt) = st(4)
            t5(1,nt) = vt(5)
            t5(2,nt) = st(5)
            t6(1,nt) = vt(6)
            t6(2,nt) = st(6)
c
c     torsional parameters for 5-membered rings
c
         else if (keyword(1:9) .eq. 'TORSION5 ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            do i = 1, 6
               vt(i) = 0.0d0
               st(i) = 0.0d0
               ft(i) = 0
            end do
            string = record(next:120)
            read (string,*,err=290,end=290)  ia,ib,ic,id,
     &                                       (vt(j),st(j),ft(j),j=1,6)
  290       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nt5 = nt5 + 1
            if (ib .lt. ic) then
               kt5(nt5) = pa//pb//pc//pd
            else if (ic .lt. ib) then
               kt5(nt5) = pd//pc//pb//pa
            else if (ia .le. id) then
               kt5(nt5) = pa//pb//pc//pd
            else if (id .lt. ia) then
               kt5(nt5) = pd//pc//pb//pa
            end if
            call torphase (ft,vt,st)
            t15(1,nt5) = vt(1)
            t15(2,nt5) = st(1)
            t25(1,nt5) = vt(2)
            t25(2,nt5) = st(2)
            t35(1,nt5) = vt(3)
            t35(2,nt5) = st(3)
            t45(1,nt5) = vt(4)
            t45(2,nt5) = st(4)
            t55(1,nt5) = vt(5)
            t55(2,nt5) = st(5)
            t65(1,nt5) = vt(6)
            t65(2,nt5) = st(6)
c
c     torsional parameters for 4-membered rings
c
         else if (keyword(1:9) .eq. 'TORSION4 ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            do i = 1, 6
               vt(i) = 0.0d0
               st(i) = 0.0d0
               ft(i) = 0
            end do
            string = record(next:120)
            read (string,*,err=300,end=300)  ia,ib,ic,id,
     &                                       (vt(i),st(i),ft(i),i=1,6)
  300       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nt4 = nt4 + 1
            if (ib .lt. ic) then
               kt4(nt4) = pa//pb//pc//pd
            else if (ic .lt. ib) then
               kt4(nt4) = pd//pc//pb//pa
            else if (ia .le. id) then
               kt4(nt4) = pa//pb//pc//pd
            else if (id .lt. ia) then
               kt4(nt4) = pd//pc//pb//pa
            end if
            call torphase (ft,vt,st)
            t14(1,nt4) = vt(1)
            t14(2,nt4) = st(1)
            t24(1,nt4) = vt(2)
            t24(2,nt4) = st(2)
            t34(1,nt4) = vt(3)
            t34(2,nt4) = st(3)
            t44(1,nt4) = vt(4)
            t44(2,nt4) = st(4)
            t54(1,nt4) = vt(5)
            t54(2,nt4) = st(5)
            t64(1,nt4) = vt(6)
            t64(2,nt4) = st(6)
c
c     pi-orbital torsion parameters
c
         else if (keyword(1:7) .eq. 'PITORS ') then
            ia = 0
            ib = 0
            pt = 0.0d0
            string = record(next:120)
            read (string,*,err=310,end=310)  ia,ib,pt
  310       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            npt = npt + 1
            if (ia .le. ib) then
               kpt(npt) = pa//pb
            else
               kpt(npt) = pb//pa
            end if
            ptcon(npt) = pt
c
c     stretch-torsion parameters
c
         else if (keyword(1:8) .eq. 'STRTORS ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            bt1 = 0.0d0
            bt2 = 0.0d0
            bt3 = 0.0d0
            string = record(next:120)
            read (string,*,err=320,end=320)  ia,ib,ic,id,bt1,bt2,bt3
  320       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nbt = nbt + 1
            if (ib .lt. ic) then
               kbt(nbt) = pa//pb//pc//pd
            else if (ic .lt. ib) then
               kbt(nbt) = pd//pc//pb//pa
            else if (ia .le. id) then
               kbt(nbt) = pa//pb//pc//pd
            else if (id .lt. ia) then
               kbt(nbt) = pd//pc//pb//pa
            end if
            btcon(1,nbt) = bt1
            btcon(2,nbt) = bt2
            btcon(3,nbt) = bt3
c
c     torsion-torsion parameters
c
         else if (keyword(1:8) .eq. 'TORTORS ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            ie = 0
            nx = 0
            ny = 0
            nxy = 0
            do i = 1, maxtgrd2
               tx(i) = 0.0d0
               ty(i) = 0.0d0
               tf(i) = 0.0d0
            end do
            string = record(next:120)
            read (string,*,err=330,end=330)  ia,ib,ic,id,ie,nx,ny
            nxy = nx * ny
            do i = 1, nxy
               iprm = iprm + 1
               record = prmline(iprm)
               read (record,*,err=330,end=330)  tx(i),ty(i),tf(i)
            end do
  330       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            call numeral (ie,pe,size)
            ntt = ntt + 1
            ktt(ntt) = pa//pb//pc//pd//pe
            nx = nxy
            call sort9 (nx,tx)
            ny = nxy
            call sort9 (ny,ty)
            tnx(ntt) = nx
            tny(ntt) = ny
            do i = 1, nx
               ttx(i,ntt) = tx(i)
            end do
            do i = 1, ny
               tty(i,ntt) = ty(i)
            end do
            do i = 1, nxy
               tbf(i,ntt) = tf(i)
            end do
c
c     atomic partial charge parameters
c
         else if (keyword(1:7) .eq. 'CHARGE ') then
            ia = 0
            cg = 0.0d0
            string = record(next:120)
            read (string,*,err=340,end=340)  ia,cg
  340       continue
            if (ia .ne. 0)  chg(ia) = cg
cc
cc     bond dipole moment parameters
cc
c         else if (keyword(1:7) .eq. 'DIPOLE ') then
c            ia = 0
c            ib = 0
c            dp = 0.0d0
c            ps = 0.5d0
c            string = record(next:120)
c            read (string,*,err=350,end=350)  ia,ib,dp,ps
c  350       continue
c            call numeral (ia,pa,size)
c            call numeral (ib,pb,size)
c            nd = nd + 1
c            if (ia .le. ib) then
c               kd(nd) = pa//pb
c            else
c               kd(nd) = pb//pa
c            end if
c            dpl(nd) = dp
c            pos(nd) = ps
cc
cc     bond dipole moment parameters for 5-membered rings
cc
c         else if (keyword(1:8) .eq. 'DIPOLE5 ') then
c            ia = 0
c            ib = 0
c            dp = 0.0d0
c            ps = 0.5d0
c            string = record(next:120)
c            read (string,*,err=360,end=360)  ia,ib,dp,ps
c  360       continue
c            call numeral (ia,pa,size)
c            call numeral (ib,pb,size)
c            nd5 = nd5 + 1
c            if (ia .le. ib) then
c               kd5(nd5) = pa//pb
c            else
c               kd5(nd5) = pb//pa
c            end if
c            dpl5(nd5) = dp
c            pos5(nd5) = ps
cc
cc     bond dipole moment parameters for 4-membered rings
cc
c         else if (keyword(1:8) .eq. 'DIPOLE4 ') then
c            ia = 0
c            ib = 0
c            dp = 0.0d0
c            ps = 0.5d0
c            string = record(next:120)
c            read (string,*,err=370,end=370)  ia,ib,dp,ps
c  370       continue
c            call numeral (ia,pa,size)
c            call numeral (ib,pb,size)
c            nd4 = nd4 + 1
c            if (ia .le. ib) then
c               kd4(nd4) = pa//pb
c            else
c               kd4(nd4) = pb//pa
c            end if
c            dpl4(nd4) = dp
c            pos4(nd4) = ps
cc
cc     bond dipole moment parameters for 3-membered rings
cc
c         else if (keyword(1:8) .eq. 'DIPOLE3 ') then
c            ia = 0
c            ib = 0
c            dp = 0.0d0
c            ps = 0.5d0
c            string = record(next:120)
c            read (string,*,err=380,end=380)  ia,ib,dp,ps
c  380       continue
c            call numeral (ia,pa,size)
c            call numeral (ib,pb,size)
c            nd3 = nd3 + 1
c            if (ia .le. ib) then
c               kd3(nd3) = pa//pb
c            else
c               kd3(nd3) = pb//pa
c            end if
c            dpl3(nd3) = dp
c            pos3(nd3) = ps
c
c     atomic multipole moment parameters
c
         else if (keyword(1:10) .eq. 'MULTIPOLE ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            axt = 'Z-then-X'
            do i = 1, 13
               pl(i) = 0.0d0
            end do
            string = record(next:120)
            read (string,*,err=390,end=390)  ia,ib,ic,id,pl(1)
            goto 420
  390       continue
            id = 0
            read (string,*,err=400,end=400)  ia,ib,ic,pl(1)
            goto 420
  400       continue
            ic = 0
            read (string,*,err=410,end=410)  ia,ib,pl(1)
            goto 420
  410       continue
            ib = 0
            read (string,*,err=430,end=430)  ia,pl(1)
  420       continue
            iprm = iprm + 1
            record = prmline(iprm)
            read (record,*,err=430,end=430)  pl(2),pl(3),pl(4)
            iprm = iprm + 1
            record = prmline(iprm)
            read (record,*,err=430,end=430)  pl(5)
            iprm = iprm + 1
            record = prmline(iprm)
            read (record,*,err=430,end=430)  pl(8),pl(9)
            iprm = iprm + 1
            record = prmline(iprm)
            read (record,*,err=430,end=430)  pl(11),pl(12),pl(13)
  430       continue
            if (ib .eq. 0)  axt = 'None'
            if (ib.ne.0 .and. ic.eq.0)  axt = 'Z-Only'
            if (ib.lt.0 .or. ic.lt.0)  axt = 'Bisector'
            if (ic.lt.0 .and. id.lt.0)  axt = 'Z-Bisect'
            if (max(ib,ic,id) .lt. 0)  axt = '3-Fold'
            ib = abs(ib)
            ic = abs(ic)
            id = abs(id)
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nmp = nmp + 1
            kmp(nmp) = pa//pb//pc//pd
            mpaxis(nmp) = axt
            multip(1,nmp) = pl(1)
            multip(2,nmp) = pl(2)
            multip(3,nmp) = pl(3)
            multip(4,nmp) = pl(4)
            multip(5,nmp) = pl(5)
            multip(6,nmp) = pl(8)
            multip(7,nmp) = pl(11)
            multip(8,nmp) = pl(8)
            multip(9,nmp) = pl(9)
            multip(10,nmp) = pl(12)
            multip(11,nmp) = pl(11)
            multip(12,nmp) = pl(12)
            multip(13,nmp) = pl(13)
c
c     atomic emtp formula parameters
c
         else if (keyword(1:8) .eq. 'SIBFACP ') then
            ia = 0
            emtp1 = 0.0d0
            emtp2 = 0.0d0
            emtp3 = 0.0d0
            string = record(next:120)
            read (string,*,err=720,end=720)  ia,emtp1,emtp2,emtp3
  720       continue
            if (ia.ne.0) then
              sibfacp(1,ia) = emtp1
              sibfacp(2,ia) = emtp2
              sibfacp(3,ia) = emtp3
            end if
c
c     emtpstar formula parameters
c
         else if (keyword(1:12) .eq. 'SIBFACPORIG ') then
            emtp1 = 0.0d0
            emtp2 = 0.0d0
            emtp3 = 0.0d0
            emtp4 = 0.0d0
            string = record(next:120)
            read (string,*,err=850,end=850)  emtp1,emtp2,emtp3,emtp4
  850       continue
            gamma1pen = emtp1
            deltapen = emtp2
            khipen = emtp3
            omegapen = emtp4
c
c     SIBFA/AMOEBA vdw radiis for charge penetration (original sibfa formulation)
c
         else if (keyword(1:6) .eq. 'VDWCP ') then
            string = record(next:120)
            read (string,*,err=860,end=860) ia,vdw1
  860       continue
            sibfacporig(ia) = vdw1
c
c     atomic dipole polarizability parameters
c
         else if (keyword(1:9) .eq. 'POLARIZE ') then
            ia = 0
            pol = 0.0d0
            thl = 0.0d0
            do i = 1, maxvalue
               pg(i) = 0
            end do
            string = record(next:120)
            read (string,*,err=440,end=440)  ia,pol,thl,
     &                                       (pg(i),i=1,maxvalue)
  440       continue
            if (ia .ne. 0) then
               polr(ia) = pol
               athl(ia) = thl
               do i = 1, maxvalue
                  pgrp(i,ia) = pg(i)
               end do
            end if
cc
cc     conjugated pisystem atom parameters
cc
c         else if (keyword(1:7) .eq. 'PIATOM ') then
c            ia = 0
c            el = 0.0d0
c            iz = 0.0d0
c            rp = 0.0d0
c            string = record(next:120)
c            read (string,*,err=450,end=450)  ia,el,iz,rp
c  450       continue
c            if (ia .ne. 0) then
c               electron(ia) = el
c               ionize(ia) = iz
c               repulse(ia) = rp
c            end if
cc
cc     conjugated pisystem bond parameters
cc
c         else if (keyword(1:7) .eq. 'PIBOND ') then
c            ia = 0
c            ib = 0
c            ss = 0.0d0
c            ts = 0.0d0
c            string = record(next:120)
c            read (string,*,err=460,end=460)  ia,ib,ss,ts
c  460       continue
c            call numeral (ia,pa,size)
c            call numeral (ib,pb,size)
c            npi = npi + 1
c            if (ia .le. ib) then
c               kpi(npi) = pa//pb
c            else
c               kpi(npi) = pb//pa
c            end if
c            sslope(npi) = ss
c            tslope(npi) = ts
cc
cc     conjugated pisystem bond parameters for 5-membered rings
cc
c         else if (keyword(1:8) .eq. 'PIBOND5 ') then
c            ia = 0
c            ib = 0
c            ss = 0.0d0
c            ts = 0.0d0
c            string = record(next:120)
c            read (string,*,err=470,end=470)  ia,ib,ss,ts
c  470       continue
c            call numeral (ia,pa,size)
c            call numeral (ib,pb,size)
c            npi5 = npi5 + 1
c            if (ia .le. ib) then
c               kpi5(npi5) = pa//pb
c            else
c               kpi5(npi5) = pb//pa
c            end if
c            sslope5(npi5) = ss
cc            tslope5(npi5) = ts
ccc
cc     conjugated pisystem bond parameters for 4-membered rings
cc
c         else if (keyword(1:8) .eq. 'PIBOND4 ') then
c            ia = 0
c            ib = 0
c            ss = 0.0d0
c            ts = 0.0d0
c            string = record(next:120)
c            read (string,*,err=480,end=480)  ia,ib,ss,ts
c  480       continue
c            call numeral (ia,pa,size)
c            call numeral (ib,pb,size)
c            npi4 = npi4 + 1
c            if (ia .le. ib) then
c               kpi4(npi4) = pa//pb
c            else
c               kpi4(npi4) = pb//pa
c            end if
c            sslope4(npi4) = ss
c            tslope4(npi4) = ts
c
c     metal ligand field splitting parameters
c
         else if (keyword(1:6) .eq. 'METAL ') then
            string = record(next:120)
            read (string,*,err=490,end=490)  ia
  490       continue
c
c     biopolymer atom type conversion definitions
c
         else if (keyword(1:8) .eq. 'BIOTYPE ') then
            ia = 0
            ib = 0
            string = record(next:120)
            read (string,*,err=500,end=500)  ia
            call getword (record,string,next)
            call getstring (record,string,next)
            string = record(next:120)
            read (string,*,err=500,end=500)  ib
  500       continue
            if (ia .ge. maxbio) then
               write (iout,40)
  510          format (/,' READPRM  --  Too many Biopolymer Types;',
     &                    ' Increase MAXBIO')
               call fatal
            end if
            if (ia .ne. 0)  biotyp(ia) = ib
c
c     MMFF van der Waals parameters
c
         else if (keyword(1:8) .eq. 'MMFFVDW ') then
            ia = 0
            rd = 0.0d0
            ep = 0.0d0
            rdn = 0.0d0
            da1 = 'C'
            string = record(next:120)
            read (string,*,err=520,end=520)  ia,rd,alphi,nni,gi,da1
  520       continue
            if (ia .ne. 0) then
               rad(ia) = rd
               g(ia) = gi
               alph(ia) = alphi
               nn(ia) = nni
               da(ia) = da1
            end if
c
c     MMFF bond stretching parameters
c
         else if (keyword(1:9) .eq. 'MMFFBOND ') then
            ia = 0
            ib = 0
            fc = 0.0d0
            bd = 0.0d0
            bt = 2
            string = record(next:120)
            read (string,*,err=530,end=530)  ia,ib,fc,bd,bt
  530       continue
            nb = nb + 1
            if (bt .eq. 0) then
               mmff_kb(ia,ib) = fc
               mmff_kb(ib,ia) = fc
               mmff_b0(ia,ib) = bd
               mmff_b0(ib,ia) = bd
            else if (bt .eq. 1) then
               mmff_kb1(ia,ib) = fc
               mmff_kb1(ib,ia) = fc
               mmff_b1(ia,ib) = bd
               mmff_b1(ib,ia) = bd
            end if
c
c     MMFF bond stretching empirical rule parameters
c
         else if (keyword(1:11) .eq. 'MMFFBONDER ') then
            ia = 0
            ib = 0
            fc = 0.0d0
            bd = 0.0d0
            string = record(next:120)
            read (string,*,err=540,end=540)  ia,ib,fc,bd
  540       continue
            r0ref(ia,ib) = fc
            r0ref(ib,ia) = fc
            kbref(ia,ib) = bd
            kbref(ib,ia) = bd
c
c     MMFF bond angle bending parameters
c
         else if (keyword(1:10) .eq. 'MMFFANGLE ') then
            ia = 0
            ib = 0
            ic = 0
            fc = 0.0d0
            an1 = 0.0d0
            at = 3
            string = record(next:120)
            read (string,*,err=550,end=550)  ia,ib,ic,fc,an1,at
  550       continue
            na = na + 1
            if (an1 .ne. 0.0d0) then
               if (at .eq. 0) then
                  mmff_ka(ia,ib,ic) = fc
                  mmff_ka(ic,ib,ia) = fc
                  mmff_ang0(ia,ib,ic) = an1
                  mmff_ang0(ic,ib,ia) = an1
               else if (at .eq. 1) then
                  mmff_ka1(ia,ib,ic) = fc
                  mmff_ka1(ic,ib,ia) = fc
                  mmff_ang1(ia,ib,ic) = an1
                  mmff_ang1(ic,ib,ia) = an1
               else if (at .eq. 2) then
                  mmff_ka2(ia,ib,ic) = fc
                  mmff_ka2(ic,ib,ia) = fc
                  mmff_ang2(ia,ib,ic) = an1
                  mmff_ang2(ic,ib,ia) = an1
               else if (at .eq. 3) then
                  mmff_ka3(ia,ib,ic) = fc
                  mmff_ka3(ic,ib,ia) = fc
                  mmff_ang3(ia,ib,ic) = an1
                  mmff_ang3(ic,ib,ia) = an1
               else if (at .eq. 4) then
                  mmff_ka4(ia,ib,ic) = fc
                  mmff_ka4(ic,ib,ia) = fc
                  mmff_ang4(ia,ib,ic) = an1
                  mmff_ang4(ic,ib,ia) = an1
               else if (at .eq. 5) then
                  mmff_ka5(ia,ib,ic) = fc
                  mmff_ka5(ic,ib,ia) = fc
                  mmff_ang5(ia,ib,ic) = an1
                  mmff_ang5(ic,ib,ia) = an1
               else if (at .eq. 6) then
                  mmff_ka6(ia,ib,ic) = fc
                  mmff_ka6(ic,ib,ia) = fc
                  mmff_ang6(ia,ib,ic) = an1
                  mmff_ang6(ic,ib,ia) = an1
               else if (at .eq. 7) then
                  mmff_ka7(ia,ib,ic) = fc
                  mmff_ka7(ic,ib,ia) = fc
                  mmff_ang7(ia,ib,ic) = an1
                  mmff_ang7(ic,ib,ia) = an1
               else if (at .eq. 8) then
                  mmff_ka8(ia,ib,ic) = fc
                  mmff_ka8(ic,ib,ia) = fc
                  mmff_ang8(ia,ib,ic) = an1
                  mmff_ang8(ic,ib,ia) = an1
               end if
            end if
c
c     MMFF stretch-bend parameters
c
         else if (keyword(1:11) .eq. 'MMFFSTRBND ') then
            ia = 0
            ib = 0
            ic = 0
            abc = 0.0d0
            cba = 0.0d0
            sbt = 4
            string = record(next:120)
            read (string,*,err=560,end=560)  ia,ib,ic,abc,cba,sbt
  560       continue
            if (ia .ne. 0) then
               if (sbt .eq. 0) then
                  stbn_abc(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc(ic,ib,ia) = cba
                  stbn_cba(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba(ic,ib,ia) = abc
               else if (sbt .eq. 1) then
                  stbn_abc1(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc1(ic,ib,ia) = cba
                  stbn_cba1(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba1(ic,ib,ia) = abc
               else if (sbt .eq. 2) then
                  stbn_abc2(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc2(ic,ib,ia) = cba
                  stbn_cba2(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba2(ic,ib,ia) = abc
               else if (sbt .eq. 3) then
                  stbn_abc3(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc3(ic,ib,ia) = cba
                  stbn_cba3(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba3(ic,ib,ia) = abc
               else if (sbt .eq. 4) then
                  stbn_abc4(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc4(ic,ib,ia) = cba
                  stbn_cba4(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba4(ic,ib,ia) = abc
               else if (sbt .eq. 5) then
                  stbn_abc5(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc5(ic,ib,ia) = cba
                  stbn_cba5(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba5(ic,ib,ia) = abc
               else if (sbt .eq. 6) then
                  stbn_abc6(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc6(ic,ib,ia) = cba
                  stbn_cba6(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba6(ic,ib,ia) = abc
               else if (sbt .eq. 7) then
                  stbn_abc7(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc7(ic,ib,ia) = cba
                  stbn_cba7(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba7(ic,ib,ia) = abc
               else if (sbt .eq. 8) then
                  stbn_abc8(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc8(ic,ib,ia) = cba
                  stbn_cba8(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba8(ic,ib,ia) = abc
               else if (sbt .eq. 9) then
                  stbn_abc9(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc9(ic,ib,ia) = cba
                  stbn_cba9(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba9(ic,ib,ia) = abc
               else if (sbt .eq. 10) then
                  stbn_abc10(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc10(ic,ib,ia) = cba
                  stbn_cba10(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba10(ic,ib,ia) = abc
               else if (sbt .eq. 11) then
                  stbn_abc11(ia,ib,ic) = abc
                  if (ic .ne. ia)  stbn_abc11(ic,ib,ia) = cba
                  stbn_cba11(ia,ib,ic) = cba
                  if (ic .ne. ia)  stbn_cba11(ic,ib,ia) = abc
               end if
            end if
c
c     MMFF out-of-plane bend parameters
c
         else if (keyword(1:11) .eq. 'MMFFOPBEND ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            fc = 0.0d0
            string = record(next:120)
            read (string,*,err=570,end=570)  ia,ib,ic,id,fc
  570       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nopb = nopb + 1
            if (ic .le. id) then
               kopb(nopb) = pa//pb//pc//pd
            else
               kopb(nopb) = pa//pb//pd//pc
            end if
            opbn(nopb) = fc
c           if (ic.gt.0 .or. id.gt.0) then
c              nopb = nopb + 1
c              if (ib .le. id) then
c                 kopb(nopb) = pc//pb//pb//pd
c              else
c                 kopb(nopb) = pc//pb//pd//pb
c              end if
c              opbn(nopb) = fc
c              nopb = nopb + 1
c              if (ia .le. ic) then
c                 kopb(nopb) = pd//pb//pa//pc
c              else
c                 kopb(nopb) = pd//pb//pc//pa
c              end if
c              opbn(nopb) = fc
c           end if
c
c     MMFF torsional parameters
c
         else if (keyword(1:12) .eq. 'MMFFTORSION ') then
            ia = 0
            ib = 0
            ic = 0
            id = 0
            do i = 1, 6
               vt(i) = 0.0d0
               st(i) = 0.0d0
               ft(i) = 0
            end do
            tt = 3
            string = record(next:120)
            read (string,*,err=580,end=580)  ia,ib,ic,id,(vt(j),
     &                                       st(j),ft(j),j=1,3),tt
  580       continue
            call numeral (ia,pa,size)
            call numeral (ib,pb,size)
            call numeral (ic,pc,size)
            call numeral (id,pd,size)
            nt = nt + 1
            if (tt .eq. 0) then
               if (ib .lt. ic) then
                  kt(nt) = pa//pb//pc//pd
               else if (ic .lt. ib) then
                  kt(nt) = pd//pc//pb//pa
               else if (ia .le. id) then
                  kt(nt) = pa//pb//pc//pd
               else if (id .lt. ia) then
                  kt(nt) = pd//pc//pb//pa
               end if
               call torphase (ft,vt,st)
               t1(1,nt) = vt(1)
               t1(2,nt) = st(1)
               t2(1,nt) = vt(2)
               t2(2,nt) = st(2)
               t3(1,nt) = vt(3)
               t3(2,nt) = st(3)
            else if (tt .eq. 1) then
               if (ib .lt. ic) then
                  kt_1(nt) = pa//pb//pc//pd
               else if (ic .lt. ib) then
                  kt_1(nt) = pd//pc//pb//pa
               else if (ia .le. id) then
                  kt_1(nt) = pa//pb//pc//pd
               else if (id .lt. ia) then
                  kt_1(nt) = pd//pc//pb//pa
               end if
               call torphase (ft,vt,st)
               t1_1(1,nt) = vt(1)
               t1_1(2,nt) = st(1)
               t2_1(1,nt) = vt(2)
               t2_1(2,nt) = st(2)
               t3_1(1,nt) = vt(3)
               t3_1(2,nt) = st(3)
            else if (tt .eq. 2) then
               if (ib .lt. ic) then
                  kt_2(nt) = pa//pb//pc//pd
               else if (ic .lt. ib) then
                  kt_2(nt) = pd//pc//pb//pa
               else if (ia .le. id) then
                  kt_2(nt) = pa//pb//pc//pd
               else if (id .lt. ia) then
                  kt_2(nt) = pd//pc//pb//pa
               end if
               call torphase (ft,vt,st)
               t1_2(1,nt) = vt(1)
               t1_2(2,nt) = st(1)
               t2_2(1,nt) = vt(2)
               t2_2(2,nt) = st(2)
               t3_2(1,nt) = vt(3)
               t3_2(2,nt) = st(3)
            else if (tt .eq. 4) then
               nt4 = nt4 + 1
               if (ib .lt. ic) then
                  kt4(nt4) = pa//pb//pc//pd
               else if (ic .lt. ib) then
                  kt4(nt4) = pd//pc//pb//pa
               else if (ia .le. id) then
                  kt4(nt4) = pa//pb//pc//pd
               else if (id .lt. ia) then
                  kt4(nt4) = pd//pc//pb//pa
               end if
               call torphase (ft,vt,st)
               t14(1,nt4) = vt(1)
               t14(2,nt4) = st(1)
               t24(1,nt4) = vt(2)
               t24(2,nt4) = st(2)
               t34(1,nt4) = vt(3)
               t34(2,nt4) = st(3)
            else if (tt .eq. 5) then
               nt5 = nt5 + 1
               if (ib .lt. ic) then
                  kt5(nt5) = pa//pb//pc//pd
               else if (ic .lt. ib) then
                  kt5(nt5) = pd//pc//pb//pa
               else if (ia .le. id) then
                  kt5(nt5) = pa//pb//pc//pd
               else if (id .lt. ia) then
                  kt5(nt5) = pd//pc//pb//pa
               end if
               call torphase (ft,vt,st)
               t15(1,nt5) = vt(1)
               t15(2,nt5) = st(1)
               t25(1,nt5) = vt(2)
               t25(2,nt5) = st(2)
               t35(1,nt5) = vt(3)
               t35(2,nt5) = st(3)
            end if
c
c     MMFF bond charge increment parameters
c
         else if (keyword(1:8) .eq. 'MMFFBCI ') then
            ia = 0
            ib = 0
            cg = 1000.0d0
            bt = 2
            string = record(next:120)
            read (string,*,err=590,end=590)  ia,ib,cg,bt
  590       continue
            if (ia .ne. 0) then
               if (bt .eq. 0) then
                  bci(ia,ib) = cg
                  bci(ib,ia) = -cg
               else if (bt .eq. 1) then
                  bci_1(ia,ib) = cg
                  bci_1(ib,ia) = -cg
               end if
            end if
c
c     MMFF partial bond charge increment parameters
c
         else if (keyword(1:9) .eq. 'MMFFPBCI ') then
            ia = 0
            string = record(next:120)
            read (string,*,err=600,end=600)  ia,cg,factor
  600       continue
            if (ia .ne. 0) then
               pbci(ia) = cg
               fcadj(ia) = factor
            end if
c
c     MMFF atom class equivalency parameters
c
         else if (keyword(1:10) .eq. 'MMFFEQUIV ') then
            string = record(next:120)
            ia = 1000
            ib = 1000
            ic = 1000
            id = 1000
            ie = 1000
            if = 0
            read (string,*,err=610,end=610)  ia,ib,ic,id,ie,if
  610       continue
            eqclass(if,1) = ia
            eqclass(if,2) = ib
            eqclass(if,3) = ic
            eqclass(if,4) = id
            eqclass(if,5) = ie
c
c     MMFF default stretch-bend parameters
c
         else if (keyword(1:12) .eq. 'MMFFDEFSTBN ') then
            string = record(next:120)
            ia = 1000
            ib = 1000
            ic = 1000
            abc = 0.0d0
            cba = 0.0d0
            read (string,*,err=620,end=620)  ia,ib,ic,abc,cba
  620       continue
            defstbn_abc(ia,ib,ic) = abc
            defstbn_cba(ia,ib,ic) = cba
            defstbn_abc(ic,ib,ia) = cba
            defstbn_cba(ic,ib,ia) = abc
c
c     MMFF covalent radius and electronegativity parameters
c
         else if (keyword(1:11) .eq. 'MMFFCOVRAD ') then
            ia = 0
            fc = 0.0d0
            bd = 0.0d0
            string = record(next:120)
            read (string,*,err=630,end=630)  ia,fc,bd
  630       continue
            rad0(ia) = fc
            paulel(ia) = bd
c
c     MMFF property parameters
c
         else if (keyword(1:9) .eq. 'MMFFPROP ') then
            string = record(next:120)
            ia = 1000
            ib = 1000
            ic = 1000
            id = 1000
            ie = 1000
            if = 1000
            ig = 1000
            ih = 1000
            ii = 1000
            read (string,*,err=640,end=640)  ia,ib,ic,id,ie,
     &                                       if,ig,ih,ii
  640       continue
            crd(ia) = ic
            val(ia) = id
            pilp(ia) = ie
            mltb(ia) = if
            arom(ia) = ig
            lin(ia) = ih
            sbmb(ia) = ii
c
c     MMFF aromatic ion parameters
c
         else if (keyword(1:9) .eq. 'MMFFAROM ') then
            string = record(next:120)
            read (string,*,err=650,end=650)  ia,ib,ic,id,ie,if
  650       continue
            if (ie.eq.0 .and. id.eq.0) then
               mmffarom(ia,if) = ic
            else if (id .eq. 1) then
               mmffaromc(ia,if) = ic
            else if (ie .eq. 1) then
               mmffaroma(ia,if) = ic
            end if
c
c     SIBFA/AMOEBA vdw radiis for charge transfer
c
        else if (keyword(1:6) .eq. 'VDWCT ') then
            string = record(next:120)
            read (string,*,err=660,end=660) ia,vdw1,vdw2
 660        continue
            sibfact1(ia) = vdw1
            sibfact2(ia) = vdw2
c
c     SIBFA/AMOEBA hybridation coefficients for charge transfer
c
       else if (keyword(1:7) .eq. 'HYBRID ') then
            string = record(next:120)
            read (string,*,err=670,end=670) ia,hybrid1,hybrid2
 670        continue
            hybrid(1,ia) = hybrid1
            hybrid(2,ia) = hybrid2
c
c     SIBFA/AMOEBA : charge transfer parameter
c
       else if (keyword(1:4) .eq. 'TAS ') then
            string = record(next:120)
            tas1 = 0.0d0
            tas2 = 0.0d0
            tas3 = 0.0d0
            tas4 = 0.0d0
            tas5 = 0.0d0
            read (string,*,err=680,end=680) ia,tas1,tas2,tas3,tas4,tas5
 680        continue
            tas(1,ia) = tas1
            tas(2,ia) = tas2
            tas(3,ia) = tas3
            tas(4,ia) = tas4
            tas(5,ia) = tas5
c
c     SIBFA/AMOEBA : charge transfer parameter
c
       else if (keyword(1:4) .eq. 'TAP ') then
            string = record(next:120)
            tap1 = 0.0d0
            tap2 = 0.0d0
            tap3 = 0.0d0
            tap4 = 0.0d0
            tap5 = 0.0d0
            read (string,*,err=690,end=690) ia,tap1,tap2,tap3,tap4,tap5
 690        continue
            tap(1,ia) = tap1
            tap(2,ia) = tap2
            tap(3,ia) = tap3
            tap(4,ia) = tap4
            tap(5,ia) = tap5
c
c     SIBFA/AMOEABA : charge transfer parameter
c
       else if (keyword(1:4) .eq. 'MA ') then
            string = record(next:120)
            ma1 = 0.0d0
            ma2 = 0.0d0
            ma3 = 0.0d0
            ma4 = 0.0d0
            ma5 = 0.0d0
            read (string,*,err=700,end=700) ia,ma1,ma2,ma3,ma4,ma5
 700        continue
            ma(1,ia) = ma1
            ma(2,ia) = ma2
            ma(3,ia) = ma3
            ma(4,ia) = ma4
            ma(5,ia) = ma5
c
c     SIBFA/AMOEABA : charge transfer parameter
c
       else if (keyword(1:4) .eq. 'IALP ') then
            string = record(next:120)
            ialp1 = 0.0d0
            ialp2 = 0.0d0
            read (string,*,err=710,end=710) ia,ialp1,ialp2
 710        continue
            ma(1,ia) = ialp1
            ma(2,ia) = ialp2
c
c     SIBFA/AMOEABA : repulsion and dispersion parameter
c
       else if (keyword(1:4) .eq. 'FORB ') then
            string = record(next:120)
            forb = 0.0d0
            read (string,*,err=730,end=730) ia,ib,orb
 730        continue
            forb(ia,ib) = orb
c
c     SIBFA/AMOEABA : repulsion vdw parameter
c
       else if (keyword(1:7) .eq. 'VDWREP ') then
            string = record(next:120)
            vdw1 = 0.0d0
            read (string,*,err=740,end=740) ia,vdw1
 740        continue
            sibfarep(ia) = vdw1
c
c     SIBFA/AMOEABA : dispersion vdw parameter
c
       else if (keyword(1:8) .eq. 'VDWDISP ') then
            string = record(next:120)
            vdw1 = 0.0d0
            vdw2 = 0.0d0
            vdw3 = 0.0d0
            read (string,*,err=750,end=750) ia,vdw1,vdw2,vdw3
 750        continue
            sibfadisp(1,ia) = vdw1
            sibfadisp(2,ia) = vdw2
            sibfadisp(3,ia) = vdw3
c
c     SIBFA/AMOEABA : dispersion vdw parameter
c
       else if (keyword(1:5) .eq. 'GORB ') then
            string = record(next:120)
            orb = 0.0d0
            read (string,*,err=760,end=760) ia,orb
 760        continue
            gorb(ia) = orb
c
c     SIBFA/AMOEABA : electronic affinity 
c
       else if (keyword(1:3) .eq. 'AE ') then
            string = record(next:120)
            orb = 0.0d0
            read (string,*,err=770,end=770) ia,aelec
 770        continue
            ae(ia) = aelec
c
c     SIBFA/AMOEABA : ionisation potential 
c
       else if (keyword(1:3) .eq. 'AH ') then
            string = record(next:120)
            orb = 0.0d0
            read (string,*,err=780,end=780) ia,aion
 780        continue
            ah(ia) = aion
c
c     SIBFA/AMOEABA : repulsion coeffs and exponent parameters
c
       else if (keyword(1:9) .eq. 'COEFFREP ') then
            string = record(next:120)
            crep11 = 0.0d0
            crep12 = 0.0d0
            read (string,*,err=790,end=790) crep11,crep12
 790        continue
            cvrep11 = crep11
            cvrep12 = crep12
            cvrep21 = 2*crep11
            cvrep22 = 2*crep12
            cvrep31 = 4*crep11
            cvrep32 = 4*crep12
      else if (keyword(1:7) .eq. 'EXPREP ') then
            string = record(next:120)
            exporep1 = 0.0d0
            exporep2 = 0.0d0
            read (string,*,err=800,end=800) exporep1,exporep2
 800        continue
            alpha = exporep1
            alpha2 = exporep2
c
c     SIBFA/AMOEABA : dispersion coeffs and exponent parameters
c
       else if (keyword(1:10) .eq. 'COEFFDISP ') then
            string = record(next:120)
            c8disp1 = 0.0d0
            c10disp1 = 0.0d0
            scdp1 = 0.0d0
            facdispij1 = 0.0d0
            bdmp1 = 0.0d0
            read (string,*,err=810,end=810) c6disp1,c8disp1,c10disp1,
     $       scdp1,facdispij1,discof1,colpa1,colp1,bdmp1
 810        continue
            c6disp = c6disp1
            c8disp = c8disp1
            c10disp = c10disp1
            scdp = scdp1
            facdispij = facdispij1
            discof = discof1
            colpa = colpa1
            colp = colp1
            bdmp = bdmp1
       else if (keyword(1:8) .eq. 'EXPDISP ') then
            string = record(next:120)
            admp61 = 0.0d0
            admp81 = 0.0d0
            admp101 = 0.0d0
            cxd1 = 0.0d0
            axd1 = 0.0d0
            cxdla1 = 0.0d0
            axdla1 = 0.0d0
            cxdlp1 = 0.0d0
            axdlp1 = 0.0d0
            read (string,*,err=820,end=820) admp61,admp81,admp101,
     $         cxd1,axd1,cxdla1,axdla1,cxdlp1,axdlp1
 820        continue
            admp6 = admp61
            admp8 = admp81
            admp10 = admp101
            cxd = cxd1
            axd = axd1
            cxdla = cxdla1
            axdla = axdla1
            cxdlp = cxdlp1
            axdlp = axdlp1
      end if
      end do
      return
      end
