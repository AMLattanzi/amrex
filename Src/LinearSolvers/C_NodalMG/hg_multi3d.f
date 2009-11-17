c-----------------------------------------------------------------------
c Note---assumes fdst linearly interpolated from cdst along face
      subroutine hgfres(
     & res,    resl0,resh0,resl1,resh1,resl2,resh2,
     & src,    srcl0,srch0,srcl1,srch1,srcl2,srch2,
     & fdst,   fdstl0,fdsth0,fdstl1,fdsth1,fdstl2,fdsth2,
     & cdst,   cdstl0,cdsth0,cdstl1,cdsth1,cdstl2,cdsth2,
     & sigmaf, sfl0,sfh0,sfl1,sfh1,sfl2,sfh2,
     & sigmac, scl0,sch0,scl1,sch1,scl2,sch2,
     &         regl0,regh0,regl1,regh1,regl2,regh2,
     & hx, hy, hz, ir, jr, kr, idim, idir,idd)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer srcl0,srch0,srcl1,srch1,srcl2,srch2
      integer fdstl0,fdsth0,fdstl1,fdsth1,fdstl2,fdsth2
      integer cdstl0,cdsth0,cdstl1,cdsth1,cdstl2,cdsth2
      integer sfl0,sfh0,sfl1,sfh1,sfl2,sfh2
      integer scl0,sch0,scl1,sch1,scl2,sch2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision res(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision src(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      double precision fdst(fdstl0:fdsth0,fdstl1:fdsth1,fdstl2:fdsth2)
      double precision cdst(cdstl0:cdsth0,cdstl1:cdsth1,cdstl2:cdsth2)
      double precision sigmaf(sfl0:sfh0,sfl1:sfh1,sfl2:sfh2)
      double precision sigmac(scl0:sch0,scl1:sch1,scl2:sch2)
      double precision hx, hy, hz
      integer ir, jr, kr, idim, idir
      integer idd
      double precision hxm2, hym2, hzm2, fac0, fac1, fac2, tmp
      integer i, j, k, is, js, ks, l, m, n

      if (idim .eq. 0) then
         i = regl0
         if (idir .eq. 1) then
            is = i - 1
         else
            is = i
         end if
         fac0 = 0.5D0 * ir / (ir + 1.0D0)
         hxm2 = 1.0D0 / (ir * ir * hx * hx)
         hym2 = 1.0D0 / (jr * jr * hy * hy)
         hzm2 = 1.0D0 / (kr * kr * hz * hz)
!$omp parallel do private(j,k)
         do k = regl2, regh2
            do j = regl1, regh1
               res(i*ir,j*jr,k*kr) =
     &           src(i*ir,j*jr,k*kr) - fac0 *
     &             (hxm2 *
     &               ((sigmac(is,j-1,k-1) + sigmac(is,j-1,k) +
     &                 sigmac(is,j,k-1)   + sigmac(is,j,k)) *
     &                 (cdst(i-idir,j,k) - cdst(i,j,k))) +
     &              hym2 *
     &               ((sigmac(is,j-1,k-1) + sigmac(is,j-1,k)) *
     &                 (cdst(i,j-1,k) - cdst(i,j,k)) +
     &                (sigmac(is,j,k-1) + sigmac(is,j,k)) *
     &                 (cdst(i,j+1,k) - cdst(i,j,k))) +
     &              hzm2 *
     &               ((sigmac(is,j-1,k-1) + sigmac(is,j,k-1)) *
     &                 (cdst(i,j,k-1) - cdst(i,j,k)) +
     &                (sigmac(is,j-1,k) + sigmac(is,j,k)) *
     &                 (cdst(i,j,k+1) - cdst(i,j,k))))
            end do
         end do
!$omp end parallel do
         fac0 = fac0 / (ir * jr * kr * jr * kr)
         hxm2 = ir * ir * hxm2
         hym2 = jr * jr * hym2
         hzm2 = kr * kr * hzm2
         i = i * ir
         if (idir .eq. 1) then
            is = i
         else
            is = i - 1
         end if
         do l = 0, kr-1
            fac2 = (kr-l) * fac0
            if (l .eq. 0) fac2 = 0.5D0 * fac2
            do n = 0, jr-1
               fac1 = (jr-n) * fac2
               if (n .eq. 0) fac1 = 0.5D0 * fac1
!$omp parallel do private(j,k,tmp)
               do k = kr*regl2, kr*regh2, kr
                  do j = jr*regl1, jr*regh1, jr
                     tmp = hxm2 *
     &                 ((sigmaf(is,j-n-1,k-l-1) + sigmaf(is,j-n-1,k-l) +
     &                   sigmaf(is,j-n,k-l-1) + sigmaf(is,j-n,k-l)) *
     &                   (fdst(i+idir,j-n,k-l) - fdst(i,j-n,k-l)) +
     &                  (sigmaf(is,j-n-1,k+l-1) + sigmaf(is,j-n-1,k+l) +
     &                   sigmaf(is,j-n,k+l-1) + sigmaf(is,j-n,k+l)) *
     &                   (fdst(i+idir,j-n,k+l) - fdst(i,j-n,k+l)) +
     &                  (sigmaf(is,j+n-1,k-l-1) + sigmaf(is,j+n-1,k-l) +
     &                   sigmaf(is,j+n,k-l-1) + sigmaf(is,j+n,k-l)) *
     &                   (fdst(i+idir,j+n,k-l) - fdst(i,j+n,k-l)) +
     &                  (sigmaf(is,j+n-1,k+l-1) + sigmaf(is,j+n-1,k+l) +
     &                   sigmaf(is,j+n,k+l-1) + sigmaf(is,j+n,k+l)) *
     &                   (fdst(i+idir,j+n,k+l) - fdst(i,j+n,k+l)))
                     tmp = tmp + hym2 *
     &                ((sigmaf(is,j-n-1,k-l-1) + sigmaf(is,j-n-1,k-l)) *
     &                   (fdst(i,j-n-1,k-l) - fdst(i,j-n,k-l)) +
     &                  (sigmaf(is,j-n,k-l-1) + sigmaf(is,j-n,k-l)) *
     &                   (fdst(i,j-n+1,k-l) - fdst(i,j-n,k-l)) +
     &                 (sigmaf(is,j-n-1,k+l-1) + sigmaf(is,j-n-1,k+l)) *
     &                   (fdst(i,j-n-1,k+l) - fdst(i,j-n,k+l)) +
     &                  (sigmaf(is,j-n,k+l-1) + sigmaf(is,j-n,k+l)) *
     &                   (fdst(i,j-n+1,k+l) - fdst(i,j-n,k+l)) +
     &                 (sigmaf(is,j+n-1,k-l-1) + sigmaf(is,j+n-1,k-l)) *
     &                   (fdst(i,j+n-1,k-l) - fdst(i,j+n,k-l)) +
     &                  (sigmaf(is,j+n,k-l-1) + sigmaf(is,j+n,k-l)) *
     &                   (fdst(i,j+n+1,k-l) - fdst(i,j+n,k-l)) +
     &                 (sigmaf(is,j+n-1,k+l-1) + sigmaf(is,j+n-1,k+l)) *
     &                   (fdst(i,j+n-1,k+l) - fdst(i,j+n,k+l)) +
     &                  (sigmaf(is,j+n,k+l-1) + sigmaf(is,j+n,k+l)) *
     &                   (fdst(i,j+n+1,k+l) - fdst(i,j+n,k+l)))
                  res(i,j,k) = res(i,j,k) - fac1 * (tmp + hzm2 *
     &                ((sigmaf(is,j-n-1,k-l-1) + sigmaf(is,j-n,k-l-1)) *
     &                   (fdst(i,j-n,k-l-1) - fdst(i,j-n,k-l)) +
     &                  (sigmaf(is,j-n-1,k-l) + sigmaf(is,j-n,k-l)) *
     &                   (fdst(i,j-n,k-l+1) - fdst(i,j-n,k-l)) +
     &                 (sigmaf(is,j-n-1,k+l-1) + sigmaf(is,j-n,k+l-1)) *
     &                   (fdst(i,j-n,k+l-1) - fdst(i,j-n,k+l)) +
     &                  (sigmaf(is,j-n-1,k+l) + sigmaf(is,j-n,k+l)) *
     &                   (fdst(i,j-n,k+l+1) - fdst(i,j-n,k+l)) +
     &                 (sigmaf(is,j+n-1,k-l-1) + sigmaf(is,j+n,k-l-1)) *
     &                   (fdst(i,j+n,k-l-1) - fdst(i,j+n,k-l)) +
     &                  (sigmaf(is,j+n-1,k-l) + sigmaf(is,j+n,k-l)) *
     &                   (fdst(i,j+n,k-l+1) - fdst(i,j+n,k-l)) +
     &                 (sigmaf(is,j+n-1,k+l-1) + sigmaf(is,j+n,k+l-1)) *
     &                   (fdst(i,j+n,k+l-1) - fdst(i,j+n,k+l)) +
     &                  (sigmaf(is,j+n-1,k+l) + sigmaf(is,j+n,k+l)) *
     &                   (fdst(i,j+n,k+l+1) - fdst(i,j+n,k+l))))
                  end do
               end do
!$omp end parallel do
            end do
         end do
      else if (idim .eq. 1) then
         j = regl1
         if (idir .eq. 1) then
            js = j - 1
         else
            js = j
         end if
         fac0 = 0.5D0 * jr / (jr + 1.0D0)
         hxm2 = 1.0D0 / (ir * ir * hx * hx)
         hym2 = 1.0D0 / (jr * jr * hy * hy)
         hzm2 = 1.0D0 / (kr * kr * hz * hz)
!$omp parallel do private(i,k)
         do k = regl2, regh2
            do i = regl0, regh0
               res(i*ir,j*jr,k*kr) =
     &           src(i*ir,j*jr,k*kr) - fac0 *
     &             (hxm2 *
     &               ((sigmac(i-1,js,k-1) + sigmac(i-1,js,k)) *
     &                 (cdst(i-1,j,k) - cdst(i,j,k)) +
     &                (sigmac(i,js,k-1) + sigmac(i,js,k)) *
     &                 (cdst(i+1,j,k) - cdst(i,j,k))) +
     &              hym2 *
     &               ((sigmac(i-1,js,k-1) + sigmac(i-1,js,k) +
     &                 sigmac(i,js,k-1)   + sigmac(i,js,k)) *
     &                 (cdst(i,j-idir,k) - cdst(i,j,k))) +
     &              hzm2 *
     &               ((sigmac(i-1,js,k-1) + sigmac(i,js,k-1)) *
     &                 (cdst(i,j,k-1) - cdst(i,j,k)) +
     &                (sigmac(i-1,js,k) + sigmac(i,js,k)) *
     &                 (cdst(i,j,k+1) - cdst(i,j,k))))
            end do
         end do
!$omp end parallel do
         fac0 = fac0 / (ir * jr * kr * ir * kr)
         hxm2 = ir * ir * hxm2
         hym2 = jr * jr * hym2
         hzm2 = kr * kr * hzm2
         j = j * jr
         if (idir .eq. 1) then
            js = j
         else
            js = j - 1
         end if
         do l = 0, kr-1
            fac2 = (kr-l) * fac0
            if (l .eq. 0) fac2 = 0.5D0 * fac2
            do m = 0, ir-1
               fac1 = (ir-m) * fac2
               if (m .eq. 0) fac1 = 0.5D0 * fac1
!$omp parallel do private(i,k,tmp)
               do k = kr*regl2, kr*regh2, kr
                  do i = ir*regl0, ir*regh0, ir
                     tmp = hxm2 *
     &                ((sigmaf(i-m-1,js,k-l-1) + sigmaf(i-m-1,js,k-l)) *
     &                   (fdst(i-m-1,j,k-l) - fdst(i-m,j,k-l)) +
     &                  (sigmaf(i-m,js,k-l-1) + sigmaf(i-m,js,k-l)) *
     &                   (fdst(i-m+1,j,k-l) - fdst(i-m,j,k-l)) +
     &                 (sigmaf(i-m-1,js,k+l-1) + sigmaf(i-m-1,js,k+l)) *
     &                   (fdst(i-m-1,j,k+l) - fdst(i-m,j,k+l)) +
     &                  (sigmaf(i-m,js,k+l-1) + sigmaf(i-m,js,k+l)) *
     &                   (fdst(i-m+1,j,k+l) - fdst(i-m,j,k+l)) +
     &                 (sigmaf(i+m-1,js,k-l-1) + sigmaf(i+m-1,js,k-l)) *
     &                   (fdst(i+m-1,j,k-l) - fdst(i+m,j,k-l)) +
     &                  (sigmaf(i+m,js,k-l-1) + sigmaf(i+m,js,k-l)) *
     &                   (fdst(i+m+1,j,k-l) - fdst(i+m,j,k-l)) +
     &                 (sigmaf(i+m-1,js,k+l-1) + sigmaf(i+m-1,js,k+l)) *
     &                   (fdst(i+m-1,j,k+l) - fdst(i+m,j,k+l)) +
     &                  (sigmaf(i+m,js,k+l-1) + sigmaf(i+m,js,k+l)) *
     &                   (fdst(i+m+1,j,k+l) - fdst(i+m,j,k+l)))
                     tmp = tmp + hym2 *
     &                 ((sigmaf(i-m-1,js,k-l-1) + sigmaf(i-m-1,js,k-l) +
     &                   sigmaf(i-m,js,k-l-1) + sigmaf(i-m,js,k-l)) *
     &                   (fdst(i-m,j+idir,k-l) - fdst(i-m,j,k-l)) +
     &                  (sigmaf(i-m-1,js,k+l-1) + sigmaf(i-m-1,js,k+l) +
     &                   sigmaf(i-m,js,k+l-1) + sigmaf(i-m,js,k+l)) *
     &                   (fdst(i-m,j+idir,k+l) - fdst(i-m,j,k+l)) +
     &                  (sigmaf(i+m-1,js,k-l-1) + sigmaf(i+m-1,js,k-l) +
     &                   sigmaf(i+m,js,k-l-1) + sigmaf(i+m,js,k-l)) *
     &                   (fdst(i+m,j+idir,k-l) - fdst(i+m,j,k-l)) +
     &                  (sigmaf(i+m-1,js,k+l-1) + sigmaf(i+m-1,js,k+l) +
     &                   sigmaf(i+m,js,k+l-1) + sigmaf(i+m,js,k+l)) *
     &                   (fdst(i+m,j+idir,k+l) - fdst(i+m,j,k+l)))
                  res(i,j,k) = res(i,j,k) - fac1 * (tmp + hzm2 *
     &                ((sigmaf(i-m-1,js,k-l-1) + sigmaf(i-m,js,k-l-1)) *
     &                   (fdst(i-m,j,k-l-1) - fdst(i-m,j,k-l)) +
     &                  (sigmaf(i-m-1,js,k-l) + sigmaf(i-m,js,k-l)) *
     &                   (fdst(i-m,j,k-l+1) - fdst(i-m,j,k-l)) +
     &                 (sigmaf(i-m-1,js,k+l-1) + sigmaf(i-m,js,k+l-1)) *
     &                   (fdst(i-m,j,k+l-1) - fdst(i-m,j,k+l)) +
     &                  (sigmaf(i-m-1,js,k+l) + sigmaf(i-m,js,k+l)) *
     &                   (fdst(i-m,j,k+l+1) - fdst(i-m,j,k+l)) +
     &                 (sigmaf(i+m-1,js,k-l-1) + sigmaf(i+m,js,k-l-1)) *
     &                   (fdst(i+m,j,k-l-1) - fdst(i+m,j,k-l)) +
     &                  (sigmaf(i+m-1,js,k-l) + sigmaf(i+m,js,k-l)) *
     &                   (fdst(i+m,j,k-l+1) - fdst(i+m,j,k-l)) +
     &                 (sigmaf(i+m-1,js,k+l-1) + sigmaf(i+m,js,k+l-1)) *
     &                   (fdst(i+m,j,k+l-1) - fdst(i+m,j,k+l)) +
     &                  (sigmaf(i+m-1,js,k+l) + sigmaf(i+m,js,k+l)) *
     &                   (fdst(i+m,j,k+l+1) - fdst(i+m,j,k+l))))
                  end do
               end do
!$omp end parallel do
            end do
         end do
      else
         k = regl2
         if (idir .eq. 1) then
            ks = k - 1
         else
            ks = k
         end if
         fac0 = 0.5D0 * kr / (kr + 1.0D0)
         hxm2 = 1.0D0 / (ir * ir * hx * hx)
         hym2 = 1.0D0 / (jr * jr * hy * hy)
         hzm2 = 1.0D0 / (kr * kr * hz * hz)
!$omp parallel do private(i,j)
         do j = regl1, regh1
            do i = regl0, regh0
               res(i*ir,j*jr,k*kr) =
     &           src(i*ir,j*jr,k*kr) - fac0 *
     &             (hxm2 *
     &               ((sigmac(i-1,j-1,ks) + sigmac(i-1,j,ks)) *
     &                 (cdst(i-1,j,k) - cdst(i,j,k)) +
     &                (sigmac(i,j-1,ks) + sigmac(i,j,ks)) *
     &                 (cdst(i+1,j,k) - cdst(i,j,k))) +
     &              hym2 *
     &               ((sigmac(i-1,j-1,ks) + sigmac(i,j-1,ks)) *
     &                 (cdst(i,j-1,k) - cdst(i,j,k)) +
     &                (sigmac(i-1,j,ks) + sigmac(i,j,ks)) *
     &                 (cdst(i,j+1,k) - cdst(i,j,k))) +
     &              hzm2 *
     &               ((sigmac(i-1,j-1,ks) + sigmac(i-1,j,ks) +
     &                 sigmac(i,j-1,ks)   + sigmac(i,j,ks)) *
     &                 (cdst(i,j,k-idir) - cdst(i,j,k))))
            end do
         end do
!$omp end parallel do
         fac0 = fac0 / (ir * jr * kr * ir * jr)
         hxm2 = ir * ir * hxm2
         hym2 = jr * jr * hym2
         hzm2 = kr * kr * hzm2
         k = k * kr
         if (idir .eq. 1) then
            ks = k
         else
            ks = k - 1
         end if
         do n = 0, jr-1
            fac2 = (jr-n) * fac0
            if (n .eq. 0) fac2 = 0.5D0 * fac2
            do m = 0, ir-1
               fac1 = (ir-m) * fac2
               if (m .eq. 0) fac1 = 0.5D0 * fac1
!$omp parallel do private(i,j,tmp)
               do j = jr*regl1, jr*regh1, jr
                  do i = ir*regl0, ir*regh0, ir
                     tmp = hxm2 *
     &                ((sigmaf(i-m-1,j-n-1,ks) + sigmaf(i-m-1,j-n,ks)) *
     &                   (fdst(i-m-1,j-n,k) - fdst(i-m,j-n,k)) +
     &                  (sigmaf(i-m,j-n-1,ks) + sigmaf(i-m,j-n,ks)) *
     &                   (fdst(i-m+1,j-n,k) - fdst(i-m,j-n,k)) +
     &                 (sigmaf(i-m-1,j+n-1,ks) + sigmaf(i-m-1,j+n,ks)) *
     &                   (fdst(i-m-1,j+n,k) - fdst(i-m,j+n,k)) +
     &                  (sigmaf(i-m,j+n-1,ks) + sigmaf(i-m,j+n,ks)) *
     &                   (fdst(i-m+1,j+n,k) - fdst(i-m,j+n,k)) +
     &                 (sigmaf(i+m-1,j-n-1,ks) + sigmaf(i+m-1,j-n,ks)) *
     &                   (fdst(i+m-1,j-n,k) - fdst(i+m,j-n,k)) +
     &                  (sigmaf(i+m,j-n-1,ks) + sigmaf(i+m,j-n,ks)) *
     &                   (fdst(i+m+1,j-n,k) - fdst(i+m,j-n,k)) +
     &                 (sigmaf(i+m-1,j+n-1,ks) + sigmaf(i+m-1,j+n,ks)) *
     &                   (fdst(i+m-1,j+n,k) - fdst(i+m,j+n,k)) +
     &                  (sigmaf(i+m,j+n-1,ks) + sigmaf(i+m,j+n,ks)) *
     &                   (fdst(i+m+1,j+n,k) - fdst(i+m,j+n,k)))
                     tmp = tmp + hym2 *
     &                ((sigmaf(i-m-1,j-n-1,ks) + sigmaf(i-m,j-n-1,ks)) *
     &                   (fdst(i-m,j-n-1,k) - fdst(i-m,j-n,k)) +
     &                  (sigmaf(i-m-1,j-n,ks) + sigmaf(i-m,j-n,ks)) *
     &                   (fdst(i-m,j-n+1,k) - fdst(i-m,j-n,k)) +
     &                 (sigmaf(i-m-1,j+n-1,ks) + sigmaf(i-m,j+n-1,ks)) *
     &                   (fdst(i-m,j+n-1,k) - fdst(i-m,j+n,k)) +
     &                  (sigmaf(i-m-1,j+n,ks) + sigmaf(i-m,j+n,ks)) *
     &                   (fdst(i-m,j+n+1,k) - fdst(i-m,j+n,k)) +
     &                 (sigmaf(i+m-1,j-n-1,ks) + sigmaf(i+m,j-n-1,ks)) *
     &                   (fdst(i+m,j-n-1,k) - fdst(i+m,j-n,k)) +
     &                  (sigmaf(i+m-1,j-n,ks) + sigmaf(i+m,j-n,ks)) *
     &                   (fdst(i+m,j-n+1,k) - fdst(i+m,j-n,k)) +
     &                 (sigmaf(i+m-1,j+n-1,ks) + sigmaf(i+m,j+n-1,ks)) *
     &                   (fdst(i+m,j+n-1,k) - fdst(i+m,j+n,k)) +
     &                  (sigmaf(i+m-1,j+n,ks) + sigmaf(i+m,j+n,ks)) *
     &                   (fdst(i+m,j+n+1,k) - fdst(i+m,j+n,k)))
                  res(i,j,k) = res(i,j,k) - fac1 * (tmp + hzm2 *
     &                 ((sigmaf(i-m-1,j-n-1,ks) + sigmaf(i-m-1,j-n,ks) +
     &                   sigmaf(i-m,j-n-1,ks) + sigmaf(i-m,j-n,ks)) *
     &                   (fdst(i-m,j-n,k+idir) - fdst(i-m,j-n,k)) +
     &                  (sigmaf(i-m-1,j+n-1,ks) + sigmaf(i-m-1,j+n,ks) +
     &                   sigmaf(i-m,j+n-1,ks) + sigmaf(i-m,j+n,ks)) *
     &                   (fdst(i-m,j+n,k+idir) - fdst(i-m,j+n,k)) +
     &                  (sigmaf(i+m-1,j-n-1,ks) + sigmaf(i+m-1,j-n,ks) +
     &                   sigmaf(i+m,j-n-1,ks) + sigmaf(i+m,j-n,ks)) *
     &                   (fdst(i+m,j-n,k+idir) - fdst(i+m,j-n,k)) +
     &                  (sigmaf(i+m-1,j+n-1,ks) + sigmaf(i+m-1,j+n,ks) +
     &                   sigmaf(i+m,j+n-1,ks) + sigmaf(i+m,j+n,ks)) *
     &                   (fdst(i+m,j+n,k+idir) - fdst(i+m,j+n,k))))
                  end do
               end do
!$omp end parallel do
            end do
         end do
      end if
      end

c end of variable density stencils
c-----------------------------------------------------------------------
c Note---assumes fdst linearly interpolated from cdst along face
      subroutine hgeres(
     & res,    resl0,resh0,resl1,resh1,resl2,resh2,
     & src,    srcl0,srch0,srcl1,srch1,srcl2,srch2,
     & fdst,   fdstl0,fdsth0,fdstl1,fdsth1,fdstl2,fdsth2,
     & cdst,   cdstl0,cdsth0,cdstl1,cdsth1,cdstl2,cdsth2,
     & sigmaf, sfl0,sfh0,sfl1,sfh1,sfl2,sfh2,
     & sigmac, scl0,sch0,scl1,sch1,scl2,sch2,
     &         regl0,regh0,regl1,regh1,regl2,regh2,
     & hx, hy, hz, ir, jr, kr, ga, ivect)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer srcl0,srch0,srcl1,srch1,srcl2,srch2
      integer fdstl0,fdsth0,fdstl1,fdsth1,fdstl2,fdsth2
      integer cdstl0,cdsth0,cdstl1,cdsth1,cdstl2,cdsth2
      integer sfl0,sfh0,sfl1,sfh1,sfl2,sfh2
      integer scl0,sch0,scl1,sch1,scl2,sch2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision res(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision src(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      double precision fdst(fdstl0:fdsth0,fdstl1:fdsth1,fdstl2:fdsth2)
      double precision cdst(cdstl0:cdsth0,cdstl1:cdsth1,cdstl2:cdsth2)
      double precision sigmaf(sfl0:sfh0,sfl1:sfh1,sfl2:sfh2)
      double precision sigmac(scl0:sch0,scl1:sch1,scl2:sch2)
      double precision hx, hy, hz
      integer ir, jr, kr, ivect(0:2), ga(0:1,0:1,0:1)
      double precision r3, hxm2, hym2, hzm2, hxm2c, hym2c, hzm2c
      double precision center, cfac, ffac, fac0, fac1, fac, tmp
      integer ic, jc, kc, if, jf, kf, ii, ji, ki, idir, jdir, kdir
      integer l, m, n
      r3 = ir * jr * kr
      hxm2c = 1.0D0 / (ir * ir * hx * hx)
      hym2c = 1.0D0 / (jr * jr * hy * hy)
      hzm2c = 1.0D0 / (kr * kr * hz * hz)
      hxm2 = ir * ir * hxm2c
      hym2 = jr * jr * hym2c
      hzm2 = kr * kr * hzm2c
      ic = regl0
      jc = regl1
      kc = regl2
      if = ic * ir
      jf = jc * jr
      kf = kc * kr
      center = 0.0D0
      if (ivect(0) .eq. 0) then
         do if = ir*regl0, ir*regh0, ir
            res(if,jf,kf) = 0.0D0
         end do
c quadrants
c each quadrant is two octants and their share of the two central edges
         fac0 = 1.0D0 / ir
         ffac = ir
         cfac = r3
         do ki = 0, 1
            kdir = 2 * ki - 1
            do ji = 0, 1
               jdir = 2 * ji - 1
               if (ga(0,ji,ki) .eq. 1) then
                  center = center + ffac
                  do m = 0, ir-1
                     fac = (ir-m) * fac0
                     if (m .eq. 0) fac = 0.5D0 * fac
                     do if = ir*regl0, ir*regh0, ir
                        tmp = hxm2 *
     &                    (sigmaf(if-m-1,jf+ji-1,kf+ki-1) *
     &                      (fdst(if-m-1,jf,kf) - fdst(if-m,jf,kf)) +
     &                     sigmaf(if-m,jf+ji-1,kf+ki-1) *
     &                      (fdst(if-m+1,jf,kf) - fdst(if-m,jf,kf)) +
     &                     sigmaf(if+m-1,jf+ji-1,kf+ki-1) *
     &                      (fdst(if+m-1,jf,kf) - fdst(if+m,jf,kf)) +
     &                     sigmaf(if+m,jf+ji-1,kf+ki-1) *
     &                      (fdst(if+m+1,jf,kf) - fdst(if+m,jf,kf)))
                        tmp = tmp + hym2 *
     &                    ((sigmaf(if-m-1,jf+ji-1,kf+ki-1) +
     &                      sigmaf(if-m,jf+ji-1,kf+ki-1)) *
     &                      (fdst(if-m,jf+jdir,kf) - fdst(if-m,jf,kf)) +
     &                     (sigmaf(if+m-1,jf+ji-1,kf+ki-1) +
     &                      sigmaf(if+m,jf+ji-1,kf+ki-1)) *
     &                      (fdst(if+m,jf+jdir,kf) - fdst(if+m,jf,kf)))
                     res(if,jf,kf) = res(if,jf,kf) + fac * (tmp + hzm2 *
     &                    ((sigmaf(if-m-1,jf+ji-1,kf+ki-1) +
     &                      sigmaf(if-m,jf+ji-1,kf+ki-1)) *
     &                      (fdst(if-m,jf,kf+kdir) - fdst(if-m,jf,kf)) +
     &                     (sigmaf(if+m-1,jf+ji-1,kf+ki-1) +
     &                      sigmaf(if+m,jf+ji-1,kf+ki-1)) *
     &                      (fdst(if+m,jf,kf+kdir) - fdst(if+m,jf,kf))))
                     end do
                  end do
               else
                  center = center + cfac
                  do ic = regl0, regh0
                     if = ic * ir
                     res(if,jf,kf) = res(if,jf,kf) + r3 *
     &                (sigmac(ic-1,jc+ji-1,kc+ki-1) *
     &                   (hxm2c * (cdst(ic-1,jc,kc) - cdst(ic,jc,kc)) +
     &                  hym2c * (cdst(ic,jc+jdir,kc) - cdst(ic,jc,kc)) +
     &                 hzm2c * (cdst(ic,jc,kc+kdir) - cdst(ic,jc,kc))) +
     &                 sigmac(ic,jc+ji-1,kc+ki-1) *
     &                   (hxm2c * (cdst(ic+1,jc,kc) - cdst(ic,jc,kc)) +
     &                  hym2c * (cdst(ic,jc+jdir,kc) - cdst(ic,jc,kc)) +
     &                  hzm2c * (cdst(ic,jc,kc+kdir) - cdst(ic,jc,kc))))
                  end do
               end if
            end do
         end do
c faces
c each face is two faces and two sides of an edge
         do ki = 0, 1
            kdir = 2 * ki - 1
            do ji = 0, 1
               jdir = 2 * ji - 1
               if (ga(0,ji,ki) - ga(0,ji,1-ki) .eq. 1) then
                  fac0 = 1.0D0 / (ir * jr)
                  ffac = ir * (jr - 1)
                  center = center + ffac
                  do n = jdir, jdir*(jr-1), jdir
                     fac1 = (jr-abs(n)) * fac0
                     do m = 0, ir-1
                        fac = (ir-m) * fac1
                        if (m .eq. 0) fac = 0.5D0 * fac
!$omp parallel do private(if,tmp)
                        do if = ir*regl0, ir*regh0, ir
                           tmp = hxm2 *
     &       ((sigmaf(if-m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if-m-1,jf+n,kf+ki-1)) *
     &         (fdst(if-m-1,jf+n,kf) - fdst(if-m,jf+n,kf)) +
     &        (sigmaf(if-m,jf+n-1,kf+ki-1)
     &            + sigmaf(if-m,jf+n,kf+ki-1)) *
     &         (fdst(if-m+1,jf+n,kf) - fdst(if-m,jf+n,kf)) +
     &        (sigmaf(if+m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m-1,jf+n,kf+ki-1)) *
     &         (fdst(if+m-1,jf+n,kf) - fdst(if+m,jf+n,kf)) +
     &        (sigmaf(if+m,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m,jf+n,kf+ki-1)) *
     &         (fdst(if+m+1,jf+n,kf) - fdst(if+m,jf+n,kf)))
                           tmp = tmp + hym2 *
     &       ((sigmaf(if-m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if-m,jf+n-1,kf+ki-1)) *
     &         (fdst(if-m,jf+n-1,kf) - fdst(if-m,jf+n,kf)) +
     &        (sigmaf(if-m-1,jf+n,kf+ki-1)
     &            + sigmaf(if-m,jf+n,kf+ki-1)) *
     &         (fdst(if-m,jf+n+1,kf) - fdst(if-m,jf+n,kf)) +
     &        (sigmaf(if+m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m,jf+n-1,kf+ki-1)) *
     &         (fdst(if+m,jf+n-1,kf) - fdst(if+m,jf+n,kf)) +
     &        (sigmaf(if+m-1,jf+n,kf+ki-1)
     &            + sigmaf(if+m,jf+n,kf+ki-1)) *
     &         (fdst(if+m,jf+n+1,kf) - fdst(if+m,jf+n,kf)))
                  res(if,jf,kf) = res(if,jf,kf)
     &            + fac * (tmp + hzm2 *
     &       ((sigmaf(if-m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if-m-1,jf+n,kf+ki-1) +
     &         sigmaf(if-m,jf+n-1,kf+ki-1)
     &            + sigmaf(if-m,jf+n,kf+ki-1)) *
     &         (fdst(if-m,jf+n,kf+kdir) - fdst(if-m,jf+n,kf)) +
     &        (sigmaf(if+m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m-1,jf+n,kf+ki-1) +
     &         sigmaf(if+m,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m,jf+n,kf+ki-1)) *
     &         (fdst(if+m,jf+n,kf+kdir) - fdst(if+m,jf+n,kf))))
                        end do
!$omp end parallel do
                     end do
                  end do
               end if
               if (ga(0,ji,ki) - ga(0,1-ji,ki) .eq. 1) then
                  fac0 = 1.0D0 / (ir * kr)
                  ffac = ir * (kr - 1)
                  center = center + ffac
                  do l = kdir, kdir*(kr-1), kdir
                     fac1 = (kr-abs(l)) * fac0
                     do m = 0, ir-1
                        fac = (ir-m) * fac1
                        if (m .eq. 0) fac = 0.5D0 * fac
!$omp parallel do private(if,tmp)
                        do if = ir*regl0, ir*regh0, ir
                           tmp = hxm2 *
     &       ((sigmaf(if-m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if-m-1,jf+ji-1,kf+l)) *
     &         (fdst(if-m-1,jf,kf+l) - fdst(if-m,jf,kf+l)) +
     &        (sigmaf(if-m,jf+ji-1,kf+l-1)
     &            + sigmaf(if-m,jf+ji-1,kf+l)) *
     &         (fdst(if-m+1,jf,kf+l) - fdst(if-m,jf,kf+l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m-1,jf+ji-1,kf+l)) *
     &         (fdst(if+m-1,jf,kf+l) - fdst(if+m,jf,kf+l)) +
     &        (sigmaf(if+m,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m,jf+ji-1,kf+l)) *
     &         (fdst(if+m+1,jf,kf+l) - fdst(if+m,jf,kf+l)))
                           tmp = tmp + hym2 *
     &       ((sigmaf(if-m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if-m-1,jf+ji-1,kf+l) +
     &         sigmaf(if-m,jf+ji-1,kf+l-1)
     &            + sigmaf(if-m,jf+ji-1,kf+l)) *
     &         (fdst(if-m,jf+jdir,kf+l) - fdst(if-m,jf,kf+l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m-1,jf+ji-1,kf+l) +
     &         sigmaf(if+m,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m,jf+ji-1,kf+l)) *
     &         (fdst(if+m,jf+jdir,kf+l) - fdst(if+m,jf,kf+l)))
                           res(if,jf,kf) = res(if,jf,kf)
     &            + fac * (tmp + hzm2 *
     &       ((sigmaf(if-m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if-m,jf+ji-1,kf+l-1)) *
     &         (fdst(if-m,jf,kf+l-1) - fdst(if-m,jf,kf+l)) +
     &        (sigmaf(if-m-1,jf+ji-1,kf+l)
     &            + sigmaf(if-m,jf+ji-1,kf+l)) *
     &         (fdst(if-m,jf,kf+l+1) - fdst(if-m,jf,kf+l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m,jf+ji-1,kf+l-1)) *
     &         (fdst(if+m,jf,kf+l-1) - fdst(if+m,jf,kf+l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf+l)
     &            + sigmaf(if+m,jf+ji-1,kf+l)) *
     &         (fdst(if+m,jf,kf+l+1) - fdst(if+m,jf,kf+l))))
                        end do
!$omp end parallel do
                     end do
                  end do
               end if
            end do
         end do
c weighting
         do if = ir*regl0, ir*regh0, ir
            res(if,jf,kf) = src(if,jf,kf) - res(if,jf,kf) / center
         end do
      else if (ivect(1) .eq. 0) then
         do jf = jr*regl1, jr*regh1, jr
            res(if,jf,kf) = 0.0D0
         end do
c quadrants
c each quadrant is two octants and their share of the two central edges
         fac0 = 1.0D0 / jr
         ffac = jr
         cfac = r3
         do ki = 0, 1
            kdir = 2 * ki - 1
            do ii = 0, 1
               idir = 2 * ii - 1
               if (ga(ii,0,ki) .eq. 1) then
                  center = center + ffac
                  do  n = 0, jr-1
                     fac = (jr-n) * fac0
                     if (n .eq. 0) fac = 0.5D0 * fac
                     do  jf = jr*regl1, jr*regh1, jr
                        tmp = hxm2 *
     &                    ((sigmaf(if+ii-1,jf-n-1,kf+ki-1) +
     &                      sigmaf(if+ii-1,jf-n,kf+ki-1)) *
     &                      (fdst(if+idir,jf-n,kf) - fdst(if,jf-n,kf)) +
     &                     (sigmaf(if+ii-1,jf+n-1,kf+ki-1) +
     &                      sigmaf(if+ii-1,jf+n,kf+ki-1)) *
     &                      (fdst(if+idir,jf+n,kf) - fdst(if,jf+n,kf)))
                        tmp = tmp + hym2 *
     &                    (sigmaf(if+ii-1,jf-n-1,kf+ki-1) *
     &                      (fdst(if,jf-n-1,kf) - fdst(if,jf-n,kf)) +
     &                     sigmaf(if+ii-1,jf-n,kf+ki-1) *
     &                      (fdst(if,jf-n+1,kf) - fdst(if,jf-n,kf)) +
     &                     sigmaf(if+ii-1,jf+n-1,kf+ki-1) *
     &                      (fdst(if,jf+n-1,kf) - fdst(if,jf+n,kf)) +
     &                     sigmaf(if+ii-1,jf+n,kf+ki-1) *
     &                      (fdst(if,jf+n+1,kf) - fdst(if,jf+n,kf)))
                     res(if,jf,kf) = res(if,jf,kf) + fac * (tmp + hzm2 *
     &                    ((sigmaf(if+ii-1,jf-n-1,kf+ki-1) +
     &                      sigmaf(if+ii-1,jf-n,kf+ki-1)) *
     &                      (fdst(if,jf-n,kf+kdir) - fdst(if,jf-n,kf)) +
     &                     (sigmaf(if+ii-1,jf+n-1,kf+ki-1) +
     &                      sigmaf(if+ii-1,jf+n,kf+ki-1)) *
     &                      (fdst(if,jf+n,kf+kdir) - fdst(if,jf+n,kf))))
                     end do
                  end do
               else
                  center = center + cfac
                  do jc = regl1, regh1
                     jf = jc * jr
                     res(if,jf,kf) = res(if,jf,kf) + r3 *
     &                (sigmac(ic+ii-1,jc-1,kc+ki-1) *
     &                 (hxm2c * (cdst(ic+idir,jc,kc) - cdst(ic,jc,kc)) +
     &                  hym2c * (cdst(ic,jc-1,kc) - cdst(ic,jc,kc)) +
     &                 hzm2c * (cdst(ic,jc,kc+kdir) - cdst(ic,jc,kc))) +
     &                 sigmac(ic+ii-1,jc,kc+ki-1) *
     &                 (hxm2c * (cdst(ic+idir,jc,kc) - cdst(ic,jc,kc)) +
     &                  hym2c * (cdst(ic,jc+1,kc) - cdst(ic,jc,kc)) +
     &                  hzm2c * (cdst(ic,jc,kc+kdir) - cdst(ic,jc,kc))))
                  end do
               end if
            end do
         end do
c faces
c each face is two faces and two sides of an edge
         do ki = 0, 1
            kdir = 2 * ki - 1
            do ii = 0, 1
               idir = 2 * ii - 1
               if (ga(ii,0,ki) - ga(ii,0,1-ki) .eq. 1) then
                  fac0 = 1.0D0 / (ir * jr)
                  ffac = jr * (ir - 1)
                  center = center + ffac
                  do n = 0, jr-1
                     fac1 = (jr-n) * fac0
                     if (n .eq. 0) fac1 = 0.5D0 * fac1
                     do m = idir, idir*(ir-1), idir
                        fac = (ir-abs(m)) * fac1
!$omp parallel do private(jf,tmp)
                        do jf = jr*regl1, jr*regh1, jr
                           tmp = hxm2 *
     &       ((sigmaf(if+m-1,jf-n-1,kf+ki-1)
     &            + sigmaf(if+m-1,jf-n,kf+ki-1)) *
     &         (fdst(if+m-1,jf-n,kf) - fdst(if+m,jf-n,kf)) +
     &        (sigmaf(if+m,jf-n-1,kf+ki-1)
     &            + sigmaf(if+m,jf-n,kf+ki-1)) *
     &         (fdst(if+m+1,jf-n,kf) - fdst(if+m,jf-n,kf)) +
     &        (sigmaf(if+m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m-1,jf+n,kf+ki-1)) *
     &         (fdst(if+m-1,jf+n,kf) - fdst(if+m,jf+n,kf)) +
     &        (sigmaf(if+m,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m,jf+n,kf+ki-1)) *
     &         (fdst(if+m+1,jf+n,kf) - fdst(if+m,jf+n,kf)))
                           tmp = tmp + hym2 *
     &       ((sigmaf(if+m-1,jf-n-1,kf+ki-1)
     &            + sigmaf(if+m,jf-n-1,kf+ki-1)) *
     &         (fdst(if+m,jf-n-1,kf) - fdst(if+m,jf-n,kf)) +
     &        (sigmaf(if+m-1,jf-n,kf+ki-1)
     &            + sigmaf(if+m,jf-n,kf+ki-1)) *
     &         (fdst(if+m,jf-n+1,kf) - fdst(if+m,jf-n,kf)) +
     &        (sigmaf(if+m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m,jf+n-1,kf+ki-1)) *
     &         (fdst(if+m,jf+n-1,kf) - fdst(if+m,jf+n,kf)) +
     &        (sigmaf(if+m-1,jf+n,kf+ki-1)
     &            + sigmaf(if+m,jf+n,kf+ki-1)) *
     &         (fdst(if+m,jf+n+1,kf) - fdst(if+m,jf+n,kf)))
                           res(if,jf,kf) = res(if,jf,kf)
     &            + fac * (tmp + hzm2 *
     &       ((sigmaf(if+m-1,jf-n-1,kf+ki-1)
     &            + sigmaf(if+m-1,jf-n,kf+ki-1) +
     &         sigmaf(if+m,jf-n-1,kf+ki-1)
     &            + sigmaf(if+m,jf-n,kf+ki-1)) *
     &         (fdst(if+m,jf-n,kf+kdir) - fdst(if+m,jf-n,kf)) +
     &        (sigmaf(if+m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m-1,jf+n,kf+ki-1) +
     &         sigmaf(if+m,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m,jf+n,kf+ki-1)) *
     &         (fdst(if+m,jf+n,kf+kdir) - fdst(if+m,jf+n,kf))))
                        end do
!$omp end parallel do
                     end do
                  end do
               end if
               if (ga(ii,0,ki) - ga(1-ii,0,ki) .eq. 1) then
                  fac0 = 1.0D0 / (jr * kr)
                  ffac = jr * (kr - 1)
                  center = center + ffac
                  do l = kdir, kdir*(kr-1), kdir
                     fac1 = (kr-abs(l)) * fac0
                     do n = 0, jr-1
                        fac = (jr-n) * fac1
                        if (n .eq. 0) fac = 0.5D0 * fac
!$omp parallel do private(jf,tmp)
                        do jf = jr*regl1, jr*regh1, jr
                           tmp = hxm2 *
     &       ((sigmaf(if+ii-1,jf-n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf-n-1,kf+l) +
     &         sigmaf(if+ii-1,jf-n,kf+l-1)
     &            + sigmaf(if+ii-1,jf-n,kf+l)) *
     &         (fdst(if+idir,jf-n,kf+l) - fdst(if,jf-n,kf+l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n-1,kf+l) +
     &         sigmaf(if+ii-1,jf+n,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n,kf+l)) *
     &         (fdst(if+idir,jf+n,kf+l) - fdst(if,jf+n,kf+l)))
                           tmp = tmp + hym2 *
     &       ((sigmaf(if+ii-1,jf-n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf-n-1,kf+l)) *
     &         (fdst(if,jf-n-1,kf+l) - fdst(if,jf-n,kf+l)) +
     &        (sigmaf(if+ii-1,jf-n,kf+l-1)
     &            + sigmaf(if+ii-1,jf-n,kf+l)) *
     &         (fdst(if,jf-n+1,kf+l) - fdst(if,jf-n,kf+l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n-1,kf+l)) *
     &         (fdst(if,jf+n-1,kf+l) - fdst(if,jf+n,kf+l)) +
     &        (sigmaf(if+ii-1,jf+n,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n,kf+l)) *
     &         (fdst(if,jf+n+1,kf+l) - fdst(if,jf+n,kf+l)))
                           res(if,jf,kf) = res(if,jf,kf)
     &            + fac * (tmp + hzm2 *
     &       ((sigmaf(if+ii-1,jf-n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf-n,kf+l-1)) *
     &         (fdst(if,jf-n,kf+l-1) - fdst(if,jf-n,kf+l)) +
     &        (sigmaf(if+ii-1,jf-n-1,kf+l)
     &            + sigmaf(if+ii-1,jf-n,kf+l)) *
     &         (fdst(if,jf-n,kf+l+1) - fdst(if,jf-n,kf+l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n,kf+l-1)) *
     &         (fdst(if,jf+n,kf+l-1) - fdst(if,jf+n,kf+l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf+l)
     &            + sigmaf(if+ii-1,jf+n,kf+l)) *
     &         (fdst(if,jf+n,kf+l+1) - fdst(if,jf+n,kf+l))))
                        end do
!$omp end parallel do
                     end do
                  end do
               end if
            end do
         end do
c weighting
         do jf = jr*regl1, jr*regh1, jr
            res(if,jf,kf) = src(if,jf,kf) - res(if,jf,kf) / center
         end do
      else
         do kf = kr*regl2, kr*regh2, kr
            res(if,jf,kf) = 0.0D0
         end do
c quadrants
c each quadrant is two octants and their share of the two central edges
         fac0 = 1.0D0 / kr
         ffac = kr
         cfac = r3
         do ji = 0, 1
            jdir = 2 * ji - 1
            do ii = 0, 1
               idir = 2 * ii - 1
               if (ga(ii,ji,0) .eq. 1) then
                  center = center + ffac
                  do l = 0, kr-1
                     fac = (kr-l) * fac0
                     if (l .eq. 0) fac = 0.5D0 * fac
                     do kf = kr*regl2, kr*regh2, kr
                        tmp = hxm2 *
     &                    ((sigmaf(if+ii-1,jf+ji-1,kf-l-1) +
     &                      sigmaf(if+ii-1,jf+ji-1,kf-l)) *
     &                      (fdst(if+idir,jf,kf-l) - fdst(if,jf,kf-l)) +
     &                     (sigmaf(if+ii-1,jf+ji-1,kf+l-1) +
     &                      sigmaf(if+ii-1,jf+ji-1,kf+l)) *
     &                      (fdst(if+idir,jf,kf+l) - fdst(if,jf,kf+l)))
                        tmp = tmp + hym2 *
     &                    ((sigmaf(if+ii-1,jf+ji-1,kf-l-1) +
     &                      sigmaf(if+ii-1,jf+ji-1,kf-l)) *
     &                      (fdst(if,jf+jdir,kf-l) - fdst(if,jf,kf-l)) +
     &                     (sigmaf(if+ii-1,jf+ji-1,kf+l-1) +
     &                      sigmaf(if+ii-1,jf+ji-1,kf+l)) *
     &                      (fdst(if,jf+jdir,kf+l) - fdst(if,jf,kf+l)))
                     res(if,jf,kf) = res(if,jf,kf) + fac * (tmp + hzm2 *
     &                    (sigmaf(if+ii-1,jf+ji-1,kf-l-1) *
     &                      (fdst(if,jf,kf-l-1) - fdst(if,jf,kf-l)) +
     &                     sigmaf(if+ii-1,jf+ji-1,kf-l) *
     &                      (fdst(if,jf,kf-l+1) - fdst(if,jf,kf-l)) +
     &                     sigmaf(if+ii-1,jf+ji-1,kf+l-1) *
     &                      (fdst(if,jf,kf+l-1) - fdst(if,jf,kf+l)) +
     &                     sigmaf(if+ii-1,jf+ji-1,kf+l) *
     &                      (fdst(if,jf,kf+l+1) - fdst(if,jf,kf+l))))
                     end do
                  end do
               else
                  center = center + cfac
                  do kc = regl2, regh2
                     kf = kc * kr
                     res(if,jf,kf) = res(if,jf,kf) + r3 *
     &                (sigmac(ic+ii-1,jc+ji-1,kc-1) *
     &                 (hxm2c * (cdst(ic+idir,jc,kc) - cdst(ic,jc,kc)) +
     &                  hym2c * (cdst(ic,jc+jdir,kc) - cdst(ic,jc,kc)) +
     &                    hzm2c * (cdst(ic,jc,kc-1) - cdst(ic,jc,kc))) +
     &                 sigmac(ic+ii-1,jc+ji-1,kc) *
     &                 (hxm2c * (cdst(ic+idir,jc,kc) - cdst(ic,jc,kc)) +
     &                  hym2c * (cdst(ic,jc+jdir,kc) - cdst(ic,jc,kc)) +
     &                    hzm2c * (cdst(ic,jc,kc+1) - cdst(ic,jc,kc))))
                  end do
               end if
            end do
         end do
c faces
c each face is two faces and two sides of an edge
         do  ji = 0, 1
            jdir = 2 * ji - 1
            do ii = 0, 1
               idir = 2 * ii - 1
               if (ga(ii,ji,0) - ga(ii,1-ji,0) .eq. 1) then
                  fac0 = 1.0D0 / (ir * kr)
                  ffac = kr * (ir - 1)
                  center = center + ffac
                  do  l = 0, kr-1
                     fac1 = (kr-l) * fac0
                     if (l .eq. 0) fac1 = 0.5D0 * fac1
                     do m = idir, idir*(ir-1), idir
                        fac = (ir-abs(m)) * fac1
!$omp parallel do private(kf,tmp)
                        do kf = kr*regl2, kr*regh2, kr
                           tmp = hxm2 *
     &       ((sigmaf(if+m-1,jf+ji-1,kf-l-1)
     &            + sigmaf(if+m-1,jf+ji-1,kf-l)) *
     &         (fdst(if+m-1,jf,kf-l) - fdst(if+m,jf,kf-l)) +
     &        (sigmaf(if+m,jf+ji-1,kf-l-1)
     &            + sigmaf(if+m,jf+ji-1,kf-l)) *
     &         (fdst(if+m+1,jf,kf-l) - fdst(if+m,jf,kf-l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m-1,jf+ji-1,kf+l)) *
     &         (fdst(if+m-1,jf,kf+l) - fdst(if+m,jf,kf+l)) +
     &        (sigmaf(if+m,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m,jf+ji-1,kf+l)) *
     &         (fdst(if+m+1,jf,kf+l) - fdst(if+m,jf,kf+l)))
                           tmp = tmp + hym2 *
     &       ((sigmaf(if+m-1,jf+ji-1,kf-l-1)
     &            + sigmaf(if+m-1,jf+ji-1,kf-l) +
     &         sigmaf(if+m,jf+ji-1,kf-l-1)
     &            + sigmaf(if+m,jf+ji-1,kf-l)) *
     &         (fdst(if+m,jf+jdir,kf-l) - fdst(if+m,jf,kf-l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m-1,jf+ji-1,kf+l) +
     &         sigmaf(if+m,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m,jf+ji-1,kf+l)) *
     &         (fdst(if+m,jf+jdir,kf+l) - fdst(if+m,jf,kf+l)))
                        res(if,jf,kf) = res(if,jf,kf)
     &            + fac * (tmp + hzm2 *
     &       ((sigmaf(if+m-1,jf+ji-1,kf-l-1)
     &            + sigmaf(if+m,jf+ji-1,kf-l-1)) *
     &         (fdst(if+m,jf,kf-l-1) - fdst(if+m,jf,kf-l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf-l)
     &            + sigmaf(if+m,jf+ji-1,kf-l)) *
     &         (fdst(if+m,jf,kf-l+1) - fdst(if+m,jf,kf-l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m,jf+ji-1,kf+l-1)) *
     &         (fdst(if+m,jf,kf+l-1) - fdst(if+m,jf,kf+l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf+l)
     &            + sigmaf(if+m,jf+ji-1,kf+l)) *
     &         (fdst(if+m,jf,kf+l+1) - fdst(if+m,jf,kf+l))))
                        end do
!$omp end parallel do
                     end do
                  end do
               end if
               if (ga(ii,ji,0) - ga(1-ii,ji,0) .eq. 1) then
                  fac0 = 1.0D0 / (jr * kr)
                  ffac = kr * (jr - 1)
                  center = center + ffac
                  do l = 0, kr-1
                     fac1 = (kr-l) * fac0
                     if (l .eq. 0) fac1 = 0.5D0 * fac1
                     do n = jdir, jdir*(jr-1), jdir
                        fac = (jr-abs(n)) * fac1
!$omp parallel do private(kf,tmp)
                        do kf = kr*regl2, kr*regh2, kr
                           tmp = hxm2 *
     &       ((sigmaf(if+ii-1,jf+n-1,kf-l-1)
     &            + sigmaf(if+ii-1,jf+n-1,kf-l) +
     &         sigmaf(if+ii-1,jf+n,kf-l-1)
     &            + sigmaf(if+ii-1,jf+n,kf-l)) *
     &         (fdst(if+idir,jf+n,kf-l) - fdst(if,jf+n,kf-l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n-1,kf+l) +
     &         sigmaf(if+ii-1,jf+n,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n,kf+l)) *
     &         (fdst(if+idir,jf+n,kf+l) - fdst(if,jf+n,kf+l)))
                           tmp = tmp + hym2 *
     &       ((sigmaf(if+ii-1,jf+n-1,kf-l-1)
     &            + sigmaf(if+ii-1,jf+n-1,kf-l)) *
     &         (fdst(if,jf+n-1,kf-l) - fdst(if,jf+n,kf-l)) +
     &        (sigmaf(if+ii-1,jf+n,kf-l-1)
     &            + sigmaf(if+ii-1,jf+n,kf-l)) *
     &         (fdst(if,jf+n+1,kf-l) - fdst(if,jf+n,kf-l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n-1,kf+l)) *
     &         (fdst(if,jf+n-1,kf+l) - fdst(if,jf+n,kf+l)) +
     &        (sigmaf(if+ii-1,jf+n,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n,kf+l)) *
     &         (fdst(if,jf+n+1,kf+l) - fdst(if,jf+n,kf+l)))
                           res(if,jf,kf) = res(if,jf,kf)
     &            + fac * (tmp + hzm2 *
     &       ((sigmaf(if+ii-1,jf+n-1,kf-l-1)
     &            + sigmaf(if+ii-1,jf+n,kf-l-1)) *
     &         (fdst(if,jf+n,kf-l-1) - fdst(if,jf+n,kf-l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf-l)
     &            + sigmaf(if+ii-1,jf+n,kf-l)) *
     &         (fdst(if,jf+n,kf-l+1) - fdst(if,jf+n,kf-l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n,kf+l-1)) *
     &         (fdst(if,jf+n,kf+l-1) - fdst(if,jf+n,kf+l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf+l)
     &            + sigmaf(if+ii-1,jf+n,kf+l)) *
     &         (fdst(if,jf+n,kf+l+1) - fdst(if,jf+n,kf+l))))
                        end do
!$omp end parallel do
                     end do
                  end do
               end if
            end do
         end do
c weighting
         do kf = kr*regl2, kr*regh2, kr
            res(if,jf,kf) = src(if,jf,kf) - res(if,jf,kf) / center
         end do
      end if
      end
c-----------------------------------------------------------------------
c Note---assumes fdst linearly interpolated from cdst along face
      subroutine hgcres(
     & res,    resl0,resh0,resl1,resh1,resl2,resh2,
     & src,    srcl0,srch0,srcl1,srch1,srcl2,srch2,
     & fdst,   fdstl0,fdsth0,fdstl1,fdsth1,fdstl2,fdsth2,
     & cdst,   cdstl0,cdsth0,cdstl1,cdsth1,cdstl2,cdsth2,
     & sigmaf, sfl0,sfh0,sfl1,sfh1,sfl2,sfh2,
     & sigmac, scl0,sch0,scl1,sch1,scl2,sch2,
     &         regl0,regh0,regl1,regh1,regl2,regh2,
     & hx, hy, hz, ir, jr, kr, ga, idd)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer srcl0,srch0,srcl1,srch1,srcl2,srch2
      integer fdstl0,fdsth0,fdstl1,fdsth1,fdstl2,fdsth2
      integer cdstl0,cdsth0,cdstl1,cdsth1,cdstl2,cdsth2
      integer sfl0,sfh0,sfl1,sfh1,sfl2,sfh2
      integer scl0,sch0,scl1,sch1,scl2,sch2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision res(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision src(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      double precision fdst(fdstl0:fdsth0,fdstl1:fdsth1,fdstl2:fdsth2)
      double precision cdst(cdstl0:cdsth0,cdstl1:cdsth1,cdstl2:cdsth2)
      double precision sigmaf(sfl0:sfh0,sfl1:sfh1,sfl2:sfh2)
      double precision sigmac(scl0:sch0,scl1:sch1,scl2:sch2)
      double precision hx, hy, hz
      integer ir, jr, kr, ga(0:1,0:1,0:1), idd
      double precision r3, hxm2, hym2, hzm2, hxm2c, hym2c, hzm2c
      double precision sum, center, cfac, ffac, fac1, fac2, fac
      integer ic, jc, kc, if, jf, kf, ii, ji, ki, idir, jdir, kdir
      integer l, m, n
      r3 = ir * jr * kr
      hxm2c = 1.0D0 / (ir * ir * hx * hx)
      hym2c = 1.0D0 / (jr * jr * hy * hy)
      hzm2c = 1.0D0 / (kr * kr * hz * hz)
      hxm2 = ir * ir * hxm2c
      hym2 = jr * jr * hym2c
      hzm2 = kr * kr * hzm2c
      ic = regl0
      jc = regl1
      kc = regl2
      if = ic * ir
      jf = jc * jr
      kf = kc * kr
      sum = 0.0D0
      center = 0.0D0
c octants
      fac = 1.0D0
      ffac = 0.5D0
      cfac = 0.5D0 * r3
      do ki = 0, 1
         kdir = 2 * ki - 1
         do ji = 0, 1
            jdir = 2 * ji - 1
            do ii = 0, 1
               idir = 2 * ii - 1
               if (ga(ii,ji,ki) .eq. 1) then
                  center = center + ffac
                  sum = sum + fac * sigmaf(if+ii-1,jf+ji-1,kf+ki-1) *
     &              (hxm2 * (fdst(if+idir,jf,kf) - fdst(if,jf,kf)) +
     &               hym2 * (fdst(if,jf+jdir,kf) - fdst(if,jf,kf)) +
     &               hzm2 * (fdst(if,jf,kf+kdir) - fdst(if,jf,kf)))
               else
                  center = center + cfac
                  sum = sum + r3 * sigmac(ic+ii-1,jc+ji-1,kc+ki-1) *
     &              (hxm2c * (cdst(ic+idir,jc,kc) - cdst(ic,jc,kc)) +
     &               hym2c * (cdst(ic,jc+jdir,kc) - cdst(ic,jc,kc)) +
     &               hzm2c * (cdst(ic,jc,kc+kdir) - cdst(ic,jc,kc)))
               end if
            end do
         end do
      end do
c faces
      do ki = 0, 1
         kdir = 2 * ki - 1
         do ji = 0, 1
            jdir = 2 * ji - 1
            do ii = 0, 1
               idir = 2 * ii - 1
               if (ga(ii,ji,ki) - ga(ii,ji,1-ki) .eq. 1) then
                  fac2 = 1.0D0 / (ir * jr)
                  ffac = 0.5D0 * (ir-1) * (jr-1)
                  center = center + ffac
                  do n = jdir, jdir*(jr-1), jdir
                     fac1 = (jr-abs(n)) * fac2
                     do m = idir, idir*(ir-1), idir
                        fac = (ir-abs(m)) * fac1
                        sum = sum + fac *
     &                    (hxm2 *
     &       ((sigmaf(if+m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m-1,jf+n,kf+ki-1)) *
     &         (fdst(if+m-1,jf+n,kf) - fdst(if+m,jf+n,kf)) +
     &        (sigmaf(if+m,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m,jf+n,kf+ki-1)) *
     &         (fdst(if+m+1,jf+n,kf) - fdst(if+m,jf+n,kf))) +
     &                     hym2 *
     &       ((sigmaf(if+m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m,jf+n-1,kf+ki-1)) *
     &         (fdst(if+m,jf+n-1,kf) - fdst(if+m,jf+n,kf)) +
     &        (sigmaf(if+m-1,jf+n,kf+ki-1)
     &            + sigmaf(if+m,jf+n,kf+ki-1)) *
     &         (fdst(if+m,jf+n+1,kf) - fdst(if+m,jf+n,kf))) +
     &                     hzm2 *
     &       ((sigmaf(if+m-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m-1,jf+n,kf+ki-1) +
     &         sigmaf(if+m,jf+n-1,kf+ki-1)
     &            + sigmaf(if+m,jf+n,kf+ki-1)) *
     &         (fdst(if+m,jf+n,kf+kdir) - fdst(if+m,jf+n,kf))))
                     end do
                  end do
               end if
               if (ga(ii,ji,ki) - ga(ii,1-ji,ki) .eq. 1) then
                  fac2 = 1.0D0 / (ir * kr)
                  ffac = 0.5D0 * (ir-1) * (kr-1)
                  center = center + ffac
                  do l = kdir, kdir*(kr-1), kdir
                     fac1 = (kr-abs(l)) * fac2
                     do m = idir, idir*(ir-1), idir
                        fac = (ir-abs(m)) * fac1
                        sum = sum + fac *
     &                    (hxm2 *
     &       ((sigmaf(if+m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m-1,jf+ji-1,kf+l)) *
     &         (fdst(if+m-1,jf,kf+l) - fdst(if+m,jf,kf+l)) +
     &        (sigmaf(if+m,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m,jf+ji-1,kf+l)) *
     &         (fdst(if+m+1,jf,kf+l) - fdst(if+m,jf,kf+l))) +
     &                     hym2 *
     &       ((sigmaf(if+m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m-1,jf+ji-1,kf+l) +
     &         sigmaf(if+m,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m,jf+ji-1,kf+l)) *
     &         (fdst(if+m,jf+jdir,kf+l) - fdst(if+m,jf,kf+l))) +
     &                     hzm2 *
     &       ((sigmaf(if+m-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+m,jf+ji-1,kf+l-1)) *
     &         (fdst(if+m,jf,kf+l-1) - fdst(if+m,jf,kf+l)) +
     &        (sigmaf(if+m-1,jf+ji-1,kf+l)
     &            + sigmaf(if+m,jf+ji-1,kf+l)) *
     &         (fdst(if+m,jf,kf+l+1) - fdst(if+m,jf,kf+l))))
                     end do
                  end do
               end if
               if (ga(ii,ji,ki) - ga(1-ii,ji,ki) .eq. 1) then
                  fac2 = 1.0D0 / (jr * kr)
                  ffac = 0.5D0 * (jr-1) * (kr-1)
                  center = center + ffac
                  do l = kdir, kdir*(kr-1), kdir
                     fac1 = (kr-abs(l)) * fac2
                     do n = jdir, jdir*(jr-1), jdir
                        fac = (jr-abs(n)) * fac1
                        sum = sum + fac *
     &                    (hxm2 *
     &       ((sigmaf(if+ii-1,jf+n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n-1,kf+l) +
     &         sigmaf(if+ii-1,jf+n,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n,kf+l)) *
     &         (fdst(if+idir,jf+n,kf+l) - fdst(if,jf+n,kf+l))) +
     &                     hym2 *
     &       ((sigmaf(if+ii-1,jf+n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n-1,kf+l)) *
     &         (fdst(if,jf+n-1,kf+l) - fdst(if,jf+n,kf+l)) +
     &        (sigmaf(if+ii-1,jf+n,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n,kf+l)) *
     &         (fdst(if,jf+n+1,kf+l) - fdst(if,jf+n,kf+l))) +
     &                     hzm2 *
     &       ((sigmaf(if+ii-1,jf+n-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+n,kf+l-1)) *
     &         (fdst(if,jf+n,kf+l-1) - fdst(if,jf+n,kf+l)) +
     &        (sigmaf(if+ii-1,jf+n-1,kf+l)
     &            + sigmaf(if+ii-1,jf+n,kf+l)) *
     &         (fdst(if,jf+n,kf+l+1) - fdst(if,jf+n,kf+l))))
                     end do
                  end do
               end if
            end do
         end do
      end do
c edges
      do ki = 0, 1
         kdir = 2 * ki - 1
         do ji = 0, 1
            jdir = 2 * ji - 1
            do ii = 0, 1
               idir = 2 * ii - 1
               if (ga(ii,ji,ki) -
     &             min(ga(ii,ji,1-ki), ga(ii,1-ji,ki), ga(ii,1-ji,1-ki))
     &             .eq. 1) then
                  fac1 = 1.0D0 / ir
                  ffac = 0.5D0 * (ir-1)
                  center = center + ffac
                  do m = idir, idir*(ir-1), idir
                     fac = (ir-abs(m)) * fac1
                     sum = sum + fac *
     &                    (hxm2 *
     &       (sigmaf(if+m-1,jf+ji-1,kf+ki-1) *
     &         (fdst(if+m-1,jf,kf) - fdst(if+m,jf,kf)) +
     &        sigmaf(if+m,jf+ji-1,kf+ki-1) *
     &         (fdst(if+m+1,jf,kf) - fdst(if+m,jf,kf))) +
     &                     hym2 *
     &       (sigmaf(if+m-1,jf+ji-1,kf+ki-1)
     &            + sigmaf(if+m,jf+ji-1,kf+ki-1)) *
     &         (fdst(if+m,jf+jdir,kf) - fdst(if+m,jf,kf)) +
     &                     hzm2 *
     &       (sigmaf(if+m-1,jf+ji-1,kf+ki-1)
     &            + sigmaf(if+m,jf+ji-1,kf+ki-1)) *
     &         (fdst(if+m,jf,kf+kdir) - fdst(if+m,jf,kf)))
                  end do
               end if
               if (ga(ii,ji,ki) -
     &             min(ga(ii,ji,1-ki), ga(1-ii,ji,ki), ga(1-ii,ji,1-ki))
     &             .eq. 1) then
                  fac1 = 1.0D0 / jr
                  ffac = 0.5D0 * (jr-1)
                  center = center + ffac
                  do n = jdir, jdir*(jr-1), jdir
                     fac = (jr-abs(n)) * fac1
                     sum = sum + fac *
     &                    (hxm2 *
     &       (sigmaf(if+ii-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+ii-1,jf+n,kf+ki-1)) *
     &         (fdst(if+idir,jf+n,kf) - fdst(if,jf+n,kf)) +
     &                     hym2 *
     &       (sigmaf(if+ii-1,jf+n-1,kf+ki-1) *
     &         (fdst(if,jf+n-1,kf) - fdst(if,jf+n,kf)) +
     &        sigmaf(if+ii-1,jf+n,kf+ki-1) *
     &         (fdst(if,jf+n+1,kf) - fdst(if,jf+n,kf))) +
     &                     hzm2 *
     &       (sigmaf(if+ii-1,jf+n-1,kf+ki-1)
     &            + sigmaf(if+ii-1,jf+n,kf+ki-1)) *
     &         (fdst(if,jf+n,kf+kdir) - fdst(if,jf+n,kf)))
                  end do
               end if
               if (ga(ii,ji,ki) -
     &             min(ga(ii,1-ji,ki), ga(1-ii,ji,ki), ga(1-ii,1-ji,ki))
     &             .eq. 1) then
                  fac1 = 1.0D0 / kr
                  ffac = 0.5D0 * (kr-1)
                  center = center + ffac
                  do l = kdir, kdir*(kr-1), kdir
                     fac = (kr-abs(l)) * fac1
                     sum = sum + fac *
     &                    (hxm2 *
     &       (sigmaf(if+ii-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+ji-1,kf+l)) *
     &         (fdst(if+idir,jf,kf+l) - fdst(if,jf,kf+l)) +
     &                     hym2 *
     &       (sigmaf(if+ii-1,jf+ji-1,kf+l-1)
     &            + sigmaf(if+ii-1,jf+ji-1,kf+l)) *
     &         (fdst(if,jf+jdir,kf+l) - fdst(if,jf,kf+l)) +
     &                     hzm2 *
     &       (sigmaf(if+ii-1,jf+ji-1,kf+l-1) *
     &         (fdst(if,jf,kf+l-1) - fdst(if,jf,kf+l)) +
     &        sigmaf(if+ii-1,jf+ji-1,kf+l) *
     &         (fdst(if,jf,kf+l+1) - fdst(if,jf,kf+l))))
                  end do
               end if
            end do
         end do
      end do
c weighting
      res(if,jf,kf) = src(if,jf,kf) - sum / center
      end
c-----------------------------------------------------------------------
c NODE-based data, factor of 2 only.
      subroutine hgints_dense(
     & dest, destl0,desth0,destl1,desth1,destl2,desth2,
     &       regl0,regh0,regl1,regh1,regl2,regh2,
     & sigx, sigy, sigz,
     &       sbl0,sbh0,sbl1,sbh1,sbl2,sbh2,
     & src,  srcl0,srch0,srcl1,srch1,srcl2,srch2,
     &       bbl0,bbh0,bbl1,bbh1,bbl2,bbh2,
     & ir, jr, kr)
      integer destl0,desth0,destl1,desth1,destl2,desth2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      integer sbl0,sbh0,sbl1,sbh1,sbl2,sbh2
      integer srcl0,srch0,srcl1,srch1,srcl2,srch2
      integer bbl0,bbh0,bbl1,bbh1,bbl2,bbh2
      integer ir, jr, kr
      double precision dest(destl0:desth0,destl1:desth1,destl2:desth2)
      double precision sigx(sbl0:sbh0,sbl1:sbh1,sbl2:sbh2)
      double precision sigy(sbl0:sbh0,sbl1:sbh1,sbl2:sbh2)
      double precision sigz(sbl0:sbh0,sbl1:sbh1,sbl2:sbh2)
      double precision src(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      integer i, j, k, ic, jc, kc
      do kc = bbl2, bbh2
         do jc = bbl1, bbh1
            do ic = bbl0, bbh0
               dest(ir*ic,jr*jc,kr*kc) = src(ic,jc,kc)
            end do
         end do
      end do
      if (ir .eq. 2) then
         do kc = bbl2, bbh2
            do jc = bbl1, bbh1
               do ic = bbl0, bbh0-1
                  i = ir * ic
                  j = jr * jc
                  k = kr * kc
                  dest(i+1,j,k) = ((sigx(i,j-1,k-1) + sigx(i,j-1,k) +
     &                              sigx(i,j,k-1) + sigx(i,j,k)) *
     &                             src(ic,jc,kc) +
     &                           (sigx(i+1,j-1,k-1) + sigx(i+1,j-1,k) +
     &                              sigx(i+1,j,k-1) + sigx(i+1,j,k)) *
     &                             src(ic+1,jc,kc)) /
     &                             (sigx(i,j-1,k-1) + sigx(i,j-1,k) +
     &                              sigx(i,j,k-1) + sigx(i,j,k) +
     &                             sigx(i+1,j-1,k-1) + sigx(i+1,j-1,k) +
     &                              sigx(i+1,j,k-1) + sigx(i+1,j,k))
               end do
            end do
         end do
      end if
      if (jr .eq. 2) then
         do kc = bbl2, bbh2
            do jc = bbl1, bbh1-1
               do ic = bbl0, bbh0
                  i = ir * ic
                  j = jr * jc
                  k = kr * kc
                  dest(i,j+1,k) = ((sigy(i-1,j,k-1) + sigy(i-1,j,k) +
     &                              sigy(i,j,k-1) + sigy(i,j,k)) *
     &                             src(ic,jc,kc) +
     &                            (sigy(i-1,j+1,k-1) + sigy(i-1,j+1,k) +
     &                              sigy(i,j+1,k-1) + sigy(i,j+1,k)) *
     &                             src(ic,jc+1,kc)) /
     &                             (sigy(i-1,j,k-1) + sigy(i-1,j,k) +
     &                              sigy(i,j,k-1) + sigy(i,j,k) +
     &                             sigy(i-1,j+1,k-1) + sigy(i-1,j+1,k) +
     &                              sigy(i,j+1,k-1) + sigy(i,j+1,k))
               end do
            end do
         end do
      end if
      if (kr .eq. 2) then
         do kc = bbl2, bbh2-1
            do jc = bbl1, bbh1
               do ic = bbl0, bbh0
                  i = ir * ic
                  j = jr * jc
                  k = kr * kc
                  dest(i,j,k+1) = ((sigz(i-1,j-1,k) + sigz(i-1,j,k) +
     &                              sigz(i,j-1,k) + sigz(i,j,k)) *
     &                             src(ic,jc,kc) +
     &                            (sigz(i-1,j-1,k+1) + sigz(i-1,j,k+1) +
     &                              sigz(i,j-1,k+1) + sigz(i,j,k+1)) *
     &                             src(ic,jc,kc+1)) /
     &                             (sigz(i-1,j-1,k) + sigz(i-1,j,k) +
     &                              sigz(i,j-1,k) + sigz(i,j,k) +
     &                             sigz(i-1,j-1,k+1) + sigz(i-1,j,k+1) +
     &                              sigz(i,j-1,k+1) + sigz(i,j,k+1))
               end do
            end do
         end do
      end if
      if (ir .eq. 2 .and. jr .eq. 2) then
         do kc = bbl2, bbh2
            do jc = bbl1, bbh1-1
               do ic = bbl0, bbh0-1
                  i = ir * ic
                  j = jr * jc
                  k = kr * kc
                  dest(i+1,j+1,k) = ((sigx(i,j,k-1) + sigx(i,j,k) +
     &                             sigx(i,j+1,k-1) + sigx(i,j+1,k)) *
     &                            dest(i,j+1,k) +
     &                            (sigx(i+1,j,k-1) + sigx(i+1,j,k) +
     &                            sigx(i+1,j+1,k-1) + sigx(i+1,j+1,k)) *
     &                            dest(i+2,j+1,k) +
     &                            (sigy(i,j,k-1) + sigy(i,j,k) +
     &                             sigy(i+1,j,k-1) + sigy(i+1,j,k)) *
     &                            dest(i+1,j,k) +
     &                            (sigy(i,j+1,k-1) + sigy(i,j+1,k) +
     &                            sigy(i+1,j+1,k-1) + sigy(i+1,j+1,k)) *
     &                            dest(i+1,j+2,k)) /
     &                           (sigx(i,j,k-1) + sigx(i,j,k) +
     &                            sigx(i,j+1,k-1) + sigx(i,j+1,k) +
     &                            sigx(i+1,j,k-1) + sigx(i+1,j,k) +
     &                            sigx(i+1,j+1,k-1) + sigx(i+1,j+1,k) +
     &                            sigy(i,j,k-1) + sigy(i,j,k) +
     &                            sigy(i+1,j,k-1) + sigy(i+1,j,k) +
     &                            sigy(i,j+1,k-1) + sigy(i,j+1,k) +
     &                            sigy(i+1,j+1,k-1) + sigy(i+1,j+1,k))
               end do
            end do
         end do
      end if
      if (ir .eq. 2 .and. kr .eq. 2) then
         do kc = bbl2, bbh2-1
            do jc = bbl1, bbh1
               do ic = bbl0, bbh0-1
                  i = ir * ic
                  j = jr * jc
                  k = kr * kc
                  dest(i+1,j,k+1) = ((sigx(i,j-1,k) + sigx(i,j-1,k+1) +
     &                             sigx(i,j,k) + sigx(i,j,k+1)) *
     &                            dest(i,j,k+1) +
     &                            (sigx(i+1,j-1,k) + sigx(i+1,j-1,k+1) +
     &                             sigx(i+1,j,k) + sigx(i+1,j,k+1)) *
     &                            dest(i+2,j,k+1) +
     &                            (sigz(i,j-1,k) + sigz(i,j,k) +
     &                             sigz(i+1,j-1,k) + sigz(i+1,j,k)) *
     &                            dest(i+1,j,k) +
     &                            (sigz(i,j-1,k+1) + sigz(i,j,k+1) +
     &                            sigz(i+1,j-1,k+1) + sigz(i+1,j,k+1)) *
     &                            dest(i+1,j,k+2)) /
     &                           (sigx(i,j-1,k) + sigx(i,j-1,k+1) +
     &                            sigx(i,j,k) + sigx(i,j,k+1) +
     &                            sigx(i+1,j-1,k) + sigx(i+1,j-1,k+1) +
     &                            sigx(i+1,j,k) + sigx(i+1,j,k+1) +
     &                            sigz(i,j-1,k) + sigz(i,j,k) +
     &                            sigz(i+1,j-1,k) + sigz(i+1,j,k) +
     &                            sigz(i,j-1,k+1) + sigz(i,j,k+1) +
     &                            sigz(i+1,j-1,k+1) + sigz(i+1,j,k+1))
               end do
            end do
         end do
      end if
      if (jr .eq. 2 .and. kr .eq. 2) then
         do kc = bbl2, bbh2-1
            do jc = bbl1, bbh1-1
               do ic = bbl0, bbh0
                  i = ir * ic
                  j = jr * jc
                  k = kr * kc
                  dest(i,j+1,k+1) = ((sigy(i-1,j,k) + sigy(i-1,j,k+1) +
     &                             sigy(i,j,k) + sigy(i,j,k+1)) *
     &                            dest(i,j,k+1) +
     &                            (sigy(i-1,j+1,k) + sigy(i-1,j+1,k+1) +
     &                             sigy(i,j+1,k) + sigy(i,j+1,k+1)) *
     &                            dest(i,j+2,k+1) +
     &                            (sigz(i-1,j,k) + sigz(i-1,j+1,k) +
     &                             sigz(i,j,k) + sigz(i,j+1,k)) *
     &                            dest(i,j+1,k) +
     &                            (sigz(i-1,j,k+1) + sigz(i-1,j+1,k+1) +
     &                             sigz(i,j,k+1) + sigz(i,j+1,k+1)) *
     &                            dest(i,j+1,k+2)) /
     &                           (sigy(i-1,j,k) + sigy(i-1,j,k+1) +
     &                            sigy(i,j,k) + sigy(i,j,k+1) +
     &                            sigy(i-1,j+1,k) + sigy(i-1,j+1,k+1) +
     &                            sigy(i,j+1,k) + sigy(i,j+1,k+1) +
     &                            sigz(i-1,j,k) + sigz(i-1,j+1,k) +
     &                            sigz(i,j,k) + sigz(i,j+1,k) +
     &                            sigz(i-1,j,k+1) + sigz(i-1,j+1,k+1) +
     &                            sigz(i,j,k+1) + sigz(i,j+1,k+1))
               end do
            end do
         end do
      end if
      if (ir .eq. 2 .and. jr .eq. 2 .and. kr .eq. 2) then
         do kc = bbl2, bbh2-1
            do jc = bbl1, bbh1-1
               do ic = bbl0, bbh0-1
                  i = ir * ic
                  j = jr * jc
                  k = kr * kc
               dest(i+1,j+1,k+1) = ((sigx(i,j,k) + sigx(i,j,k+1) +
     &                               sigx(i,j+1,k) + sigx(i,j+1,k+1)) *
     &                              dest(i,j+1,k+1) +
     &                              (sigx(i+1,j,k) + sigx(i+1,j,k+1) +
     &                            sigx(i+1,j+1,k) + sigx(i+1,j+1,k+1)) *
     &                              dest(i+2,j+1,k+1) +
     &                              (sigy(i,j,k) + sigy(i,j,k+1) +
     &                               sigy(i+1,j,k) + sigy(i+1,j,k+1)) *
     &                              dest(i+1,j,k+1) +
     &                              (sigy(i,j+1,k) + sigy(i,j+1,k+1) +
     &                            sigy(i+1,j+1,k) + sigy(i+1,j+1,k+1)) *
     &                              dest(i+1,j+2,k+1) +
     &                              (sigz(i,j,k) + sigz(i,j+1,k) +
     &                               sigz(i+1,j,k) + sigz(i+1,j+1,k)) *
     &                              dest(i+1,j+1,k) +
     &                              (sigz(i,j,k+1) + sigz(i,j+1,k+1) +
     &                            sigz(i+1,j,k+1) + sigz(i+1,j+1,k+1)) *
     &                              dest(i+1,j+1,k+2))
               dest(i+1,j+1,k+1) = dest(i+1,j+1,k+1) /
     &                             (sigx(i,j,k) + sigx(i,j,k+1) +
     &                              sigx(i,j+1,k) + sigx(i,j+1,k+1) +
     &                              sigx(i+1,j,k) + sigx(i+1,j,k+1) +
     &                             sigx(i+1,j+1,k) + sigx(i+1,j+1,k+1) +
     &                              sigy(i,j,k) + sigy(i,j,k+1) +
     &                              sigy(i+1,j,k) + sigy(i+1,j,k+1) +
     &                              sigy(i,j+1,k) + sigy(i,j+1,k+1) +
     &                             sigy(i+1,j+1,k) + sigy(i+1,j+1,k+1) +
     &                              sigz(i,j,k) + sigz(i,j+1,k) +
     &                              sigz(i+1,j,k) + sigz(i+1,j+1,k) +
     &                              sigz(i,j,k+1) + sigz(i,j+1,k+1) +
     &                              sigz(i+1,j,k+1) + sigz(i+1,j+1,k+1))
               end do
            end do
         end do
      end if
      end
c-----------------------------------------------------------------------
c NODE-based data, factor of 2 only.
      subroutine hgints(
     & dest,  destl0,desth0,destl1,desth1,destl2,desth2,
     &        regl0,regh0,regl1,regh1,regl2,regh2,
     & signd, snl0,snh0,snl1,snh1,snl2,snh2,
     & src,   srcl0,srch0,srcl1,srch1,srcl2,srch2,
     &        bbl0,bbh0,bbl1,bbh1,bbl2,bbh2,
     & ir, jr, kr)
      integer destl0,desth0,destl1,desth1,destl2,desth2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      integer snl0,snh0,snl1,snh1,snl2,snh2
      integer srcl0,srch0,srcl1,srch1,srcl2,srch2
      integer bbl0,bbh0,bbl1,bbh1,bbl2,bbh2
      integer ir, jr, kr
      double precision dest(destl0:desth0,destl1:desth1,destl2:desth2)
      double precision signd(snl0:snh0,snl1:snh1,snl2:snh2, 3)
      double precision src(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      integer i, j, k, ic, jc, kc
      do kc = bbl2, bbh2
         do jc = bbl1, bbh1
            do ic = bbl0, bbh0
               dest(ir*ic,jr*jc,kr*kc) = src(ic,jc,kc)
            end do
         end do
      end do
      if (ir .eq. 2) then
!$omp parallel do private(i,j,k,ic,jc,kc) if((bbh2-bbl2).ge.3)
         do kc = bbl2, bbh2
            k = kr * kc
            do jc = bbl1, bbh1
               j = jr * jc
               do ic = bbl0, bbh0-1
                  i = 2 * ic
                  dest(i+1,j,k) = (signd(i,j,k,1)   * src(ic,jc,kc) +
     &                          signd(i+1,j,k,1) * src(ic+1,jc,kc)) /
     &                         (signd(i,j,k,1) + signd(i+1,j,k,1))
               end do
            end do
         end do
!$omp end parallel do
      end if
      if (jr .eq. 2) then
!$omp parallel do private(i,j,k,ic,jc,kc) if((bbh2-bbl2).ge.3)
         do kc = bbl2, bbh2
            k = kr * kc
            do jc = bbl1, bbh1-1
               j = 2 * jc
               do ic = bbl0, bbh0
                  i = ir * ic
                  dest(i,j+1,k) = (signd(i,j,k,2)   * src(ic,jc,kc) +
     &                          signd(i,j+1,k,2) * src(ic,jc+1,kc)) /
     &                         (signd(i,j,k,2) + signd(i,j+1,k,2))
               end do
            end do
         end do
!$omp end parallel do
      end if
      if (kr .eq. 2) then
!$omp parallel do private(i,j,k,ic,jc,kc) if((bbh2-bbl2).ge.3)
         do kc = bbl2, bbh2-1
            k = 2 * kc
            do jc = bbl1, bbh1
               j = jr * jc
               do ic = bbl0, bbh0
                  i = ir * ic
                  dest(i,j,k+1) = (signd(i,j,k,3)   * src(ic,jc,kc) +
     &                          signd(i,j,k+1,3) * src(ic,jc,kc+1)) /
     &                         (signd(i,j,k,3) + signd(i,j,k+1,3))
               end do
            end do
         end do
!$omp end parallel do
      end if
      if (ir .eq. 2 .and. jr .eq. 2) then
!$omp parallel do private(i,j,k,ic,jc,kc) if((bbh2-bbl2).ge.3)
         do kc = bbl2, bbh2
            k = kr * kc
            do jc = bbl1, bbh1-1
               j = 2 * jc
               do ic = bbl0, bbh0-1
                  i = 2 * ic
                 dest(i+1,j+1,k) = (signd(i,j+1,k,1)   * dest(i,j+1,k) +
     &                            signd(i+1,j+1,k,1) * dest(i+2,j+1,k) +
     &                            signd(i+1,j,k,2)   * dest(i+1,j,k) +
     &                           signd(i+1,j+1,k,2) * dest(i+1,j+2,k)) /
     &                          (signd(i,j+1,k,1) + signd(i+1,j+1,k,1) +
     &                            signd(i+1,j,k,2) + signd(i+1,j+1,k,2))
               end do
            end do
         end do
!$omp end parallel do
      end if
      if (ir .eq. 2 .and. kr .eq. 2) then
!$omp parallel do private(i,j,k,ic,jc,kc) if((bbh1-bbl1).ge.3)
         do jc = bbl1, bbh1
            j = jr * jc
            do kc = bbl2, bbh2-1
               k = 2 * kc
               do ic = bbl0, bbh0-1
                  i = 2 * ic
               dest(i+1,j,k+1) = (signd(i,j,k+1,1)   * dest(i,j,k+1) +
     &                            signd(i+1,j,k+1,1) * dest(i+2,j,k+1) +
     &                            signd(i+1,j,k,3)   * dest(i+1,j,k) +
     &                           signd(i+1,j,k+1,3) * dest(i+1,j,k+2)) /
     &                          (signd(i,j,k+1,1) + signd(i+1,j,k+1,1) +
     &                            signd(i+1,j,k,3) + signd(i+1,j,k+1,3))
               end do
            end do
         end do
!$omp end parallel do
      end if
      if (jr .eq. 2 .and. kr .eq. 2) then
!$omp parallel do private(i,j,k,ic,jc,kc) if((bbh0-bbl0).ge.3)
         do ic = bbl0, bbh0
            i = ir * ic
            do kc = bbl2, bbh2-1
               k = 2 * kc
               do jc = bbl1, bbh1-1
                  j = 2 * jc
                 dest(i,j+1,k+1) = (signd(i,j,k+1,2)   * dest(i,j,k+1) +
     &                            signd(i,j+1,k+1,2) * dest(i,j+2,k+1) +
     &                            signd(i,j+1,k,3)   * dest(i,j+1,k) +
     &                           signd(i,j+1,k+1,3) * dest(i,j+1,k+2)) /
     &                          (signd(i,j,k+1,2) + signd(i,j+1,k+1,2) +
     &                            signd(i,j+1,k,3) + signd(i,j+1,k+1,3))
               end do
            end do
         end do
!$omp end parallel do
      end if
      if (ir .eq. 2 .and. jr .eq. 2 .and. kr .eq. 2) then
         do kc = bbl2, bbh2-1
            k = 2 * kc
            do jc = bbl1, bbh1-1
               j = 2 * jc
               do ic = bbl0, bbh0-1
                  i = 2 * ic
                  dest(i+1,j+1,k+1) =
     &                (signd(i,j+1,k+1,1)   * dest(i,j+1,k+1) +
     &                 signd(i+1,j+1,k+1,1) * dest(i+2,j+1,k+1) +
     &                 signd(i+1,j,k+1,2)   * dest(i+1,j,k+1) +
     &                 signd(i+1,j+1,k+1,2) * dest(i+1,j+2,k+1) +
     &                 signd(i+1,j+1,k,3)   * dest(i+1,j+1,k) +
     &                 signd(i+1,j+1,k+1,3) * dest(i+1,j+1,k+2)) /
     &                 (signd(i,j+1,k+1,1) + signd(i+1,j+1,k+1,1) +
     &                  signd(i+1,j,k+1,2) + signd(i+1,j+1,k+1,2) +
     &                  signd(i+1,j+1,k,3) + signd(i+1,j+1,k+1,3))
               end do
            end do
         end do
      end if
      end
c-----------------------------------------------------------------------
c CELL-based data only.
      subroutine hgsrst(
     & destx, desty, destz,
     &     destl0,desth0,destl1,desth1,destl2,desth2,
     &     regl0,regh0,regl1,regh1,regl2,regh2,
     & srcx, srcy, srcz,
     &     srcl0,srch0,srcl1,srch1,srcl2,srch2,
     & ir, jr, kr)
      integer destl0,desth0,destl1,desth1,destl2,desth2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      integer srcl0,srch0,srcl1,srch1,srcl2,srch2
      integer ir, jr, kr
      double precision destx(destl0:desth0,destl1:desth1,destl2:desth2)
      double precision desty(destl0:desth0,destl1:desth1,destl2:desth2)
      double precision destz(destl0:desth0,destl1:desth1,destl2:desth2)
      double precision srcx(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      double precision srcy(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      double precision srcz(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      integer i, j, k, i2, j2, k2
      if (ir .ne. 2 .and. jr .ne. 2 .and. kr .ne. 2) then
          stop "this can't happen"
      endif

!$omp parallel private(i,j,k,i2,j2,k2) if((regh2-regl2).ge.3)
      if (ir .eq. 2 .and. jr .eq. 2 .and. kr .eq. 2) then
!$omp do
         do k = regl2, regh2
            k2 = 2 * k
            do j = regl1, regh1
               j2 = 2 * j
               do i = regl0, regh0
                  i2 = 2 * i
                  destx(i,j,k) = 0.5D0 / (1.0D0 / (srcx(i2,j2,k2) +
     &                                            srcx(i2,j2,k2+1) +
     &                                            srcx(i2,j2+1,k2) +
     &                                            srcx(i2,j2+1,k2+1)) +
     &                                    1.0D0 / (srcx(i2+1,j2,k2) +
     &                                            srcx(i2+1,j2,k2+1) +
     &                                            srcx(i2+1,j2+1,k2) +
     &                                            srcx(i2+1,j2+1,k2+1)))
                  desty(i,j,k) = 0.5D0 / (1.0D0 / (srcy(i2,j2,k2) +
     &                                            srcy(i2,j2,k2+1) +
     &                                            srcy(i2+1,j2,k2) +
     &                                            srcy(i2+1,j2,k2+1)) +
     &                                    1.0D0 / (srcy(i2,j2+1,k2) +
     &                                            srcy(i2,j2+1,k2+1) +
     &                                            srcy(i2+1,j2+1,k2) +
     &                                            srcy(i2+1,j2+1,k2+1)))
                  destz(i,j,k) = 0.5D0 / (1.0D0 / (srcz(i2,j2,k2) +
     &                                            srcz(i2,j2+1,k2) +
     &                                            srcz(i2+1,j2,k2) +
     &                                            srcz(i2+1,j2+1,k2)) +
     &                                    1.0D0 / (srcz(i2,j2,k2+1) +
     &                                            srcz(i2,j2+1,k2+1) +
     &                                            srcz(i2+1,j2,k2+1) +
     &                                            srcz(i2+1,j2+1,k2+1)))
               end do
            end do
         end do
!$omp end do
      else if (ir .eq. 2 .and. jr .eq. 2) then
!$omp do
         do k = regl2, regh2
            do j = regl1, regh1
               j2 = 2 * j
               do i = regl0, regh0
                  i2 = 2 * i
                  destx(i,j,k) = 1.0D0 / (1.0D0 / (srcx(i2,j2,k) +
     &                                           srcx(i2,j2+1,k)) +
     &                                   1.0D0 / (srcx(i2+1,j2,k) +
     &                                           srcx(i2+1,j2+1,k)))
                  desty(i,j,k) = 1.0D0 / (1.0D0 / (srcy(i2,j2,k) +
     &                                           srcy(i2+1,j2,k)) +
     &                                   1.0D0 / (srcy(i2,j2+1,k) +
     &                                           srcy(i2+1,j2+1,k)))
                  destz(i,j,k) = 0.25D0 * (srcz(i2,j2,k) +
     &                                     srcz(i2,j2+1,k) +
     &                                     srcz(i2+1,j2,k) +
     &                                     srcz(i2+1,j2+1,k))
               end do
            end do
         end do
!$omp end do
      else if (ir .eq. 2 .and. kr .eq. 2) then
!$omp do
         do k = regl2, regh2
            k2 = 2 * k
            do j = regl1, regh1
               do i = regl0, regh0
                  i2 = 2 * i
                  destx(i,j,k) = 1.0D0 / (1.0D0 / (srcx(i2,j,k2) +
     &                                           srcx(i2,j,k2+1)) +
     &                                   1.0D0 / (srcx(i2+1,j,k2) +
     &                                           srcx(i2+1,j,k2+1)))
                  desty(i,j,k) = 0.25D0 * (srcy(i2,j,k2) +
     &                                     srcy(i2,j,k2+1) +
     &                                     srcy(i2+1,j,k2) +
     &                                     srcy(i2+1,j,k2+1))
                  destz(i,j,k) = 1.0D0 / (1.0D0 / (srcz(i2,j,k2) +
     &                                           srcz(i2+1,j,k2)) +
     &                                   1.0D0 / (srcz(i2,j,k2+1) +
     &                                           srcz(i2+1,j,k2+1)))
               end do
            end do
         end do
!$omp end do
      else if (jr .eq. 2 .and. kr .eq. 2) then
!$omp do
         do k = regl2, regh2
            k2 = 2 * k
            do j = regl1, regh1
               j2 = 2 * j
               do i = regl0, regh0
                  destx(i,j,k) = 0.25D0 * (srcx(i,j2,k2) +
     &                                     srcx(i,j2,k2+1) +
     &                                     srcx(i,j2+1,k2) +
     &                                     srcx(i,j2+1,k2+1))
                  desty(i,j,k) = 1.0D0 / (1.0D0 / (srcy(i,j2,k2) +
     &                                           srcy(i,j2,k2+1)) +
     &                                   1.0D0 / (srcy(i,j2+1,k2) +
     &                                           srcy(i,j2+1,k2+1)))
                  destz(i,j,k) = 1.0D0 / (1.0D0 / (srcz(i,j2,k2) +
     &                                           srcz(i,j2+1,k2)) +
     &                                   1.0D0 / (srcz(i,j2,k2+1) +
     &                                           srcz(i,j2+1,k2+1)))
               end do
            end do
         end do
!$omp end do
      else if (ir .eq. 2) then
!$omp do
         do k = regl2, regh2
            do j = regl1, regh1
               do i = regl0, regh0
                  i2 = 2 * i
                  destx(i,j,k) = 2.0D0 / (1.0D0 / srcx(i2,j,k) +
     &                                   1.0D0 / srcx(i2+1,j,k))
                  desty(i,j,k) = 0.5D0 * (srcy(i2,j,k) +
     &                                    srcy(i2+1,j,k))
                  destz(i,j,k) = 0.5D0 * (srcz(i2,j,k) +
     &                                    srcz(i2+1,j,k))
               end do
            end do
         end do
!$omp end do
      else if (jr .eq. 2) then
!$omp do
         do k = regl2, regh2
            do j = regl1, regh1
               j2 = 2 * j
               do i = regl0, regh0
                  destx(i,j,k) = 0.5D0 * (srcx(i,j2,k) +
     &                                    srcx(i,j2+1,k))
                  desty(i,j,k) = 2.0D0 / (1.0D0 / srcy(i,j2,k) +
     &                                   1.0D0 / srcy(i,j2+1,k))
                  destz(i,j,k) = 0.5D0 * (srcz(i,j2,k) +
     &                                    srcz(i,j2+1,k))
               end do
            end do
         end do
!$omp end do
      else if (kr .eq. 2) then
!$omp do
         do k = regl2, regh2
            k2 = 2 * k
            do j = regl1, regh1
               do i = regl0, regh0
                  destx(i,j,k) = 0.5D0 * (srcx(i,j,k2) +
     &                                    srcx(i,j,k2+1))
                  desty(i,j,k) = 0.5D0 * (srcy(i,j,k2) +
     &                                    srcy(i,j,k2+1))
                  destz(i,j,k) = 2.0D0 / (1.0D0 / srcz(i,j,k2) +
     &                                   1.0D0 / srcz(i,j,k2+1))
               end do
            end do
         end do
!$omp end do
      end if
!$omp end parallel
      end
c seven-point variable stencils
c-----------------------------------------------------------------------
      subroutine hgcen(
     & cen,   cenl0,cenh0,cenl1,cenh1,cenl2,cenh2,
     & signd, snl0,snh0,snl1,snh1,snl2,snh2,
     &        regl0,regh0,regl1,regh1,regl2,regh2,idd)
      integer cenl0,cenh0,cenl1,cenh1,cenl2,cenh2
      integer snl0,snh0,snl1,snh1,snl2,snh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision cen(cenl0:cenh0,cenl1:cenh1,cenl2:cenh2)
      double precision signd(snl0:snh0,snl1:snh1,snl2:snh2, 3)
      double precision tmp
      integer i, j, k
      integer idd
!$omp parallel do private(i,j,k,tmp) if((regh2-regl2).ge.3)
      do k = regl2, regh2
         do j = regl1, regh1
            do i = regl0, regh0
               tmp = (signd(i-1,j,k,1) + signd(i,j,k,1) 
     &              + signd(i,j-1,k,2) + signd(i,j,k,2)
     &              + signd(i,j,k-1,3) + signd(i,j,k,3))
               if ( tmp .eq. 0.0D0 ) then
                  cen(i,j,k) = 0.0D0
               else
                  cen(i,j,k) = 1.0D0 / tmp
               end if
            end do
         end do
      end do
!$omp end parallel do
      end
c-----------------------------------------------------------------------
c sig here contains three different directions all stored on "nodes"
      subroutine hgrlxu(
     & cor, res, sig, cen,
     &     resl0,resh0,resl1,resh1,resl2,resh2,
     & mask,
     &     regl0,regh0,regl1,regh1,regl2,regh2,idd)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision cor(*)
      double precision res(*)
      double precision sig(*)
      double precision cen(*)
      double precision mask(*)
      double precision AVG
      integer i, jdiff, kdiff, ly, lz
      integer idd

      AVG() = (sig(i-1)        * cor(i-1) +
     &         sig(i)          * cor(i+1) +
     &         sig(i+ly-jdiff) * cor(i-jdiff) +
     &         sig(i+ly)       * cor(i+jdiff) +
     &         sig(i+lz-kdiff) * cor(i-kdiff) +
     &         sig(i+lz)       * cor(i+kdiff))
      jdiff =  resh0 - resl0 + 1
      kdiff = (resh1 - resl1 + 1) * jdiff
      ly    = (resh2 - resl2 + 1) * kdiff
      lz    = 2 * ly

!$omp parallel do private(i)
      do i = (regl2 - resl2) * kdiff + (regl1 - resl1) * jdiff +
     &          (regl0 - resl0) + 1,
     &          (regh2 - resl2) * kdiff + (regh1 - resl1) * jdiff +
     &          (regh0 - resl0) + 1, 2
         cor(i) = cor(i)
     &      + mask(i) * ((AVG() - res(i)) * cen(i) - cor(i))
      end do
!$omp end parallel do

!$omp parallel do private(i)
      do i = (regl2 - resl2) * kdiff + (regl1 - resl1) * jdiff +
     &          (regl0 - resl0) + 2,
     &          (regh2 - resl2) * kdiff + (regh1 - resl1) * jdiff +
     &          (regh0 - resl0) + 1, 2
         cor(i) = cor(i)
     &      + mask(i) * ((AVG() - res(i)) * cen(i) - cor(i))
      end do
!$omp end parallel do
      end

c-----------------------------------------------------------------------
c sig here contains three different directions all stored on "nodes"
c MLW: Strip-mining modification for NEC SX6
c MLW: For partially vectorized loops that require vector temporaries
c MLW: The compiler guesses at the length of the loop and issues a 
c MLW: run-time error if vector length is larger.  
c MLW: Can extend the size of the temporary with
c MLW: the LOOPCNT directive, but it will not vectorize the loop
c MLW: if this value is too large (~ 15000).  Decided to explicitly
c MLW: stripmine the loop.
c MLW: NOTE: Only will be called on NEC SX6
      subroutine hgrlxu_sx(
     & cor, res, sig, cen,
     &     resl0,resh0,resl1,resh1,resl2,resh2,
     & mask,
     &     regl0,regh0,regl1,regh1,regl2,regh2,idd)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision cor(*)
      double precision res(*)
      double precision sig(*)
      double precision cen(*)
      double precision mask(*)
      double precision AVG
      integer i, jdiff, kdiff, ly, lz
      integer idd
      integer striplen, istart, iend, ilen, istop
      AVG() = (sig(i-1)        * cor(i-1) +
     &         sig(i)          * cor(i+1) +
     &         sig(i+ly-jdiff) * cor(i-jdiff) +
     &         sig(i+ly)       * cor(i+jdiff) +
     &         sig(i+lz-kdiff) * cor(i-kdiff) +
     &         sig(i+lz)       * cor(i+kdiff))
      jdiff =  resh0 - resl0 + 1
      kdiff = (resh1 - resl1 + 1) * jdiff
      ly    = (resh2 - resl2 + 1) * kdiff
      lz    = 2 * ly
c     IMPORTANT: striplen must be an even number less than LOOPCNT     
      striplen = 5000
c     Do the Red cells
      istart = (regl2 - resl2) * kdiff + (regl1 - resl1) * jdiff +
     &          (regl0 - resl0) + 1
      iend   = (regh2 - resl2) * kdiff + (regh1 - resl1) * jdiff +
     &          (regh0 - resl0) + 1
      do while (istart <= iend)
         ilen = min(striplen,iend-istart+1)
         istop = istart + ilen - 1
!CDIR LOOPCNT=5500
         do i = istart, istop, 2
            cor(i) = cor(i)
     &           + mask(i) * ((AVG() - res(i)) * cen(i) - cor(i))
         end do
         istart = istart + ilen
      end do
c     Do the Black cells (shifted over by one)
      istart = (regl2 - resl2) * kdiff + (regl1 - resl1) * jdiff +
     &          (regl0 - resl0) + 2
      do while (istart <= iend)
         ilen = min(striplen,iend-istart+1)
         istop = istart + ilen - 1
!CDIR LOOPCNT=5500
         do i = istart, istop, 2
            cor(i) = cor(i)
     &           + mask(i) * ((AVG() - res(i)) * cen(i) - cor(i))
         end do
         istart = istart + ilen
      end do
      end

c-----------------------------------------------------------------------
c sig here contains three different directions all stored on "nodes"
      subroutine hgrlxur(
     & cor, res, signd, cen,
     &     resl0,resh0,resl1,resh1,resl2,resh2,
     &     regl0,regh0,regl1,regh1,regl2,regh2,idd)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision cor(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision res(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision signd(resl0:resh0,resl1:resh1,resl2:resh2,3)
      double precision cen(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision AVG
      integer i, j, k, ipar0, ipass, jdiff, kdiff, ly, lz
      integer idd, ipar
      AVG() = (signd(i-1,j,k,1) * cor(i-1,j,k) +
     &         signd(i,j,k,1)   * cor(i+1,j,k) +
     &         signd(i,j-1,k,2) * cor(i,j-1,k) +
     &         signd(i,j,k,2)   * cor(i,j+1,k) +
     &         signd(i,j,k-1,3) * cor(i,j,k-1) +
     &         signd(i,j,k,3)   * cor(i,j,k+1))
      do ipass = 0, 1
         ipar0 = ipass
         do k = regl2, regh2
            ipar0 = 1 - ipar0
            ipar = ipar0
            do j = regl1, regh1
               ipar = 1 - ipar
               do i = regl0 + ipar, regh0, 2
                  cor(i,j,k) = (AVG() - res(i,j,k)) * cen(i,j,k)
               end do
            end do
         end do
      end do
      end
c-----------------------------------------------------------------------
      subroutine hgrlx(
     & cor,   corl0,corh0,corl1,corh1,corl2,corh2,
     & res,   resl0,resh0,resl1,resh1,resl2,resh2,
     & signd, snl0,snh0,snl1,snh1,snl2,snh2,
     & cen,   cenl0,cenh0,cenl1,cenh1,cenl2,cenh2,
     &        regl0,regh0,regl1,regh1,regl2,regh2)
      integer corl0,corh0,corl1,corh1,corl2,corh2
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer snl0,snh0,snl1,snh1,snl2,snh2
      integer cenl0,cenh0,cenl1,cenh1,cenl2,cenh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision cor(corl0:corh0,corl1:corh1,corl2:corh2)
      double precision res(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision signd(snl0:snh0,snl1:snh1,snl2:snh2, 3)
      double precision cen(cenl0:cenh0,cenl1:cenh1,cenl2:cenh2)
      integer i, j, k, ipar0, ipar, ipass
      double precision AVG
      AVG() = (signd(i-1,j,k,1) * cor(i-1,j,k) +
     &         signd(i,j,k,1)   * cor(i+1,j,k) +
     &         signd(i,j-1,k,2) * cor(i,j-1,k) +
     &         signd(i,j,k,2)   * cor(i,j+1,k) +
     &         signd(i,j,k-1,3) * cor(i,j,k-1) +
     &         signd(i,j,k,3)   * cor(i,j,k+1))
      do ipass = 0, 1
         ipar0 = ipass
         do k = regl2, regh2
            ipar0 = 1 - ipar0
            ipar = ipar0
            do j = regl1, regh1
               ipar = 1 - ipar
               do i = regl0 + ipar, regh0, 2
                  cor(i,j,k) = (AVG() - res(i,j,k)) * cen(i,j,k)
               end do
            end do
         end do
      end do
      end
c-----------------------------------------------------------------------
      subroutine hgres(
     & res,   resl0,resh0,resl1,resh1,resl2,resh2,
     & src,   srcl0,srch0,srcl1,srch1,srcl2,srch2,
     & dest,  destl0,desth0,destl1,desth1,destl2,desth2,
     & signd, snl0,snh0,snl1,snh1,snl2,snh2,
     &        regl0,regh0,regl1,regh1,regl2,regh2)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer srcl0,srch0,srcl1,srch1,srcl2,srch2
      integer destl0,desth0,destl1,desth1,destl2,desth2
      integer snl0,snh0,snl1,snh1,snl2,snh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision res(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision src(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      double precision dest(destl0:desth0,destl1:desth1,destl2:desth2)
      double precision signd(snl0:snh0,snl1:snh1,snl2:snh2, 3)
      integer i, j, k
!$omp parallel do private(i,j,k)
      do k = regl2, regh2
         do j = regl1, regh1
            do i = regl0, regh0
               res(i,j,k) = src(i,j,k) -
     &        (signd(i-1,j,k,1) * (dest(i-1,j,k) - dest(i,j,k)) +
     &         signd(i,j,k,1)   * (dest(i+1,j,k) - dest(i,j,k)) +
     &         signd(i,j-1,k,2) * (dest(i,j-1,k) - dest(i,j,k)) +
     &         signd(i,j,k,2)   * (dest(i,j+1,k) - dest(i,j,k)) +
     &         signd(i,j,k-1,3) * (dest(i,j,k-1) - dest(i,j,k)) +
     &         signd(i,j,k,3)   * (dest(i,j,k+1) - dest(i,j,k)))
            end do
         end do
      end do
!$omp end parallel do
      end
c-----------------------------------------------------------------------
      subroutine hgresu(
     & res, resl0,resh0,resl1,resh1,resl2,resh2,
     & src, dest, signd, mask,
     &      regl0,regh0,regl1,regh1,regl2,regh2,
     & idd)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision res(*)
      double precision src(*)
      double precision dest(*)
      double precision signd(*)
      double precision mask(*)
      integer i, jdiff, kdiff, ly, lz
      integer idd
      jdiff = resh0 - resl0 + 1
      kdiff = (resh1 - resl1 + 1) * jdiff
      ly    = (resh2 - resl2 + 1) * kdiff
      lz    = 2 * ly
!$omp parallel do private(i)
      do i = (regl2 - resl2) * kdiff + (regl1 - resl1) * jdiff +
     &          (regl0 - resl0) + 1,
     &          (regh2 - resl2) * kdiff + (regh1 - resl1) * jdiff +
     &          (regh0 - resl0) + 1
         res(i) = mask(i) * (src(i) -
     &     (signd(i-1)        * (dest(i-1) - dest(i)) +
     &      signd(i)          * (dest(i+1) - dest(i)) +
     &      signd(i+ly-jdiff) * (dest(i-jdiff) - dest(i)) +
     &      signd(i+ly)       * (dest(i+jdiff) - dest(i)) +
     &      signd(i+lz-kdiff) * (dest(i-kdiff) - dest(i)) +
     &      signd(i+lz)       * (dest(i+kdiff) - dest(i))))
      end do
!$omp end parallel do
      end
c-----------------------------------------------------------------------
      subroutine hgresur(
     & res, resl0,resh0,resl1,resh1,resl2,resh2,
     & src, dest, signd,
     &      regl0,regh0,regl1,regh1,regl2,regh2,
     & idd)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision res(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision src(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision dest(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision signd(resl0:resh0,resl1:resh1,resl2:resh2,3)
      integer i, j, k, jdiff, kdiff, ly, lz
      integer idd
!$omp parallel do private(i,j,k)
      do k = regl2, regh2
         do j = regl1, regh1
            do i = regl0, regh0
               res(i,j,k) = src(i,j,k) -
     &        (signd(i-1,j,k,1) * (dest(i-1,j,k) - dest(i,j,k)) +
     &         signd(i,j,k,1)   * (dest(i+1,j,k) - dest(i,j,k)) +
     &         signd(i,j-1,k,2) * (dest(i,j-1,k) - dest(i,j,k)) +
     &         signd(i,j,k,2)   * (dest(i,j+1,k) - dest(i,j,k)) +
     &         signd(i,j,k-1,3) * (dest(i,j,k-1) - dest(i,j,k)) +
     &         signd(i,j,k,3)   * (dest(i,j,k+1) - dest(i,j,k)))
            end do
         end do
      end do
!$omp end parallel do
      end
c-----------------------------------------------------------------------
      subroutine hgscon(
     & signd, snl0,snh0,snl1,snh1,snl2,snh2,
     & sigx, sigy, sigz,
     &        scl0,sch0,scl1,sch1,scl2,sch2,
     &        regl0,regh0,regl1,regh1,regl2,regh2,
     & hx, hy, hz)
      integer snl0,snh0,snl1,snh1,snl2,snh2
      integer scl0,sch0,scl1,sch1,scl2,sch2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision signd(snl0:snh0,snl1:snh1,snl2:snh2, 3)
      double precision sigx(scl0:sch0,scl1:sch1,scl2:sch2)
      double precision sigy(scl0:sch0,scl1:sch1,scl2:sch2)
      double precision sigz(scl0:sch0,scl1:sch1,scl2:sch2)
      double precision hx, hy, hz
      double precision facx, facy, facz
      integer i, j, k
      facx = 0.25D0 / (hx*hx)
      facy = 0.25D0 / (hy*hy)
      facz = 0.25D0 / (hz*hz)
!$omp parallel private(i,j,k) if((regh2-regl2).ge.3)
!$omp do
      do k = regl2, regh2
         do j = regl1, regh1
            do i = regl0-1, regh0
               signd(i,j,k,1) = facx *
     &               (sigx(i,j-1,k-1) + sigx(i,j-1,k) +
     &                sigx(i,j,k-1)   + sigx(i,j,k))
            end do
         end do
      end do
!$omp end do nowait
!$omp do
      do k = regl2, regh2
         do j = regl1-1, regh1
            do i = regl0, regh0
               signd(i,j,k,2) = facy *
     &               (sigy(i-1,j,k-1) + sigy(i-1,j,k) +
     &                sigy(i,j,k-1)   + sigy(i,j,k))
            end do
         end do
      end do
!$omp end do nowait
!$omp do
      do k = regl2-1, regh2
         do j = regl1, regh1
            do i = regl0, regh0
               signd(i,j,k,3) = facz *
     &               (sigz(i-1,j-1,k) + sigz(i-1,j,k) +
     &                sigz(i,j-1,k)   + sigz(i,j,k))
            end do
         end do
      end do
!$omp end do nowait
!$omp end parallel
      end
c-----------------------------------------------------------------------
      subroutine hgrlx_no_sigma(
     & cor, corl0,corh0,corl1,corh1,corl2,corh2,
     & res, resl0,resh0,resl1,resh1,resl2,resh2,
     & sigx, sigy, sigz,
     &      sfl0,sfh0,sfl1,sfh1,sfl2,sfh2,
     & cen, cenl0,cenh0,cenl1,cenh1,cenl2,cenh2,
     &      regl0,regh0,regl1,regh1,regl2,regh2,
     & hx, hy, hz)
      integer corl0,corh0,corl1,corh1,corl2,corh2
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer sfl0,sfh0,sfl1,sfh1,sfl2,sfh2
      integer cenl0,cenh0,cenl1,cenh1,cenl2,cenh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision cor(corl0:corh0,corl1:corh1,corl2:corh2)
      double precision res(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision sigx(sfl0:sfh0,sfl1:sfh1,sfl2:sfh2)
      double precision sigy(sfl0:sfh0,sfl1:sfh1,sfl2:sfh2)
      double precision sigz(sfl0:sfh0,sfl1:sfh1,sfl2:sfh2)
      double precision cen(cenl0:cenh0,cenl1:cenh1,cenl2:cenh2)
      double precision hx, hy, hz, hxm2, hym2, hzm2
      double precision AVG
      integer i, j, k, ipass, ipar, ipar0
      AVG() = 0.25D0 * (hxm2 *
     &          ((sigx(i-1,j-1,k-1) + sigx(i-1,j-1,k) +
     &            sigx(i-1,j,k-1)   + sigx(i-1,j,k)) * cor(i-1,j,k) +
     &           (sigx(i,j-1,k-1)   + sigx(i,j-1,k) +
     &            sigx(i,j,k-1)     + sigx(i,j,k)) * cor(i+1,j,k)) +
     &                 hym2 *
     &          ((sigy(i-1,j-1,k-1) + sigy(i-1,j-1,k) +
     &            sigy(i,j-1,k-1)   + sigy(i,j-1,k)) * cor(i,j-1,k) +
     &           (sigy(i-1,j,k-1)   + sigy(i-1,j,k) +
     &            sigy(i,j,k-1)     + sigy(i,j,k)) * cor(i,j+1,k)) +
     &                 hzm2 *
     &          ((sigz(i-1,j-1,k-1) + sigz(i-1,j,k-1) +
     &            sigz(i,j-1,k-1)   + sigz(i,j,k-1)) * cor(i,j,k-1) +
     &           (sigz(i-1,j-1,k)   + sigz(i-1,j,k) +
     &            sigz(i,j-1,k)     + sigz(i,j,k)) * cor(i,j,k+1)))
      hxm2 = 1.0D0 / (hx*hx)
      hym2 = 1.0D0 / (hy*hy)
      hzm2 = 1.0D0 / (hz*hz)
      do ipass = 0, 1
         ipar0 = ipass
         do k = regl2, regh2
            ipar0 = 1 - ipar0
            ipar = ipar0
            do j = regl1, regh1
               ipar = 1 - ipar
               do i = regl0 + ipar, regh0, 2
                  cor(i,j,k) = (AVG() - res(i,j,k)) * cen(i,j,k)
               end do
            end do
         end do
      end do
      end
c-----------------------------------------------------------------------
      subroutine hgres_no_sigma(
     & res,  resl0,resh0,resl1,resh1,resl2,resh2,
     & src,  srcl0,srch0,srcl1,srch1,srcl2,srch2,
     & dest, destl0,desth0,destl1,desth1,destl2,desth2,
     & sigx, sigy, sigz,
     &       sfl0,sfh0,sfl1,sfh1,sfl2,sfh2,
     &       regl0,regh0,regl1,regh1,regl2,regh2,
     & hx, hy, hz)
      integer resl0,resh0,resl1,resh1,resl2,resh2
      integer srcl0,srch0,srcl1,srch1,srcl2,srch2
      integer destl0,desth0,destl1,desth1,destl2,desth2
      integer sfl0,sfh0,sfl1,sfh1,sfl2,sfh2
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision res(resl0:resh0,resl1:resh1,resl2:resh2)
      double precision src(srcl0:srch0,srcl1:srch1,srcl2:srch2)
      double precision dest(destl0:desth0,destl1:desth1,destl2:desth2)
      double precision sigx(sfl0:sfh0,sfl1:sfh1,sfl2:sfh2)
      double precision sigy(sfl0:sfh0,sfl1:sfh1,sfl2:sfh2)
      double precision sigz(sfl0:sfh0,sfl1:sfh1,sfl2:sfh2)
      double precision hx, hy, hz, hxm2, hym2, hzm2
      integer i, j, k
      hxm2 = 1.0D0 / (hx*hx)
      hym2 = 1.0D0 / (hy*hy)
      hzm2 = 1.0D0 / (hz*hz)
!$omp parallel do private(i,j,k) if((regh2-regl2).ge.3)
         do k = regl2, regh2
            do j = regl1, regh1
               do i = regl0, regh0
                  res(i,j,k) = src(i,j,k) - 0.25D0 *        (hxm2 *
     &              ((sigx(i-1,j-1,k-1) + sigx(i-1,j-1,k) +
     &                sigx(i-1,j,k-1)   + sigx(i-1,j,k)) *
     &                (dest(i-1,j,k) - dest(i,j,k)) +
     &               (sigx(i,j-1,k-1)   + sigx(i,j-1,k) +
     &                sigx(i,j,k-1)     + sigx(i,j,k)) *
     &                (dest(i+1,j,k) - dest(i,j,k))) +       hym2 *
     &              ((sigy(i-1,j-1,k-1) + sigy(i-1,j-1,k) +
     &                sigy(i,j-1,k-1)   + sigy(i,j-1,k)) *
     &                (dest(i,j-1,k) - dest(i,j,k)) +
     &               (sigy(i-1,j,k-1)   + sigy(i-1,j,k) +
     &                sigy(i,j,k-1)     + sigy(i,j,k)) *
     &                (dest(i,j+1,k) - dest(i,j,k))) +       hzm2 *
     &              ((sigz(i-1,j-1,k-1) + sigz(i-1,j,k-1) +
     &                sigz(i,j-1,k-1)   + sigz(i,j,k-1)) *
     &                (dest(i,j,k-1) - dest(i,j,k)) +
     &               (sigz(i-1,j-1,k)   + sigz(i-1,j,k) +
     &                sigz(i,j-1,k)     + sigz(i,j,k)) *
     &                (dest(i,j,k+1) - dest(i,j,k)))             )
               end do
            end do
         end do
!$omp end parallel do
      end
c-----------------------------------------------------------------------
c Unrolled indexing in these 3 routines uses the fact that each array
c has a border of width 1
c-----------------------------------------------------------------------
c Works for NODE-based data.
      subroutine hgip(
     & v0, v1, mask,
     &     regl0,regh0,regl1,regh1,regl2,regh2,
     & sum)
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision v0(*)
      double precision v1(*)
      double precision mask(*)
      double precision sum
      integer i, jdiff, kdiff
      jdiff = regh0 - regl0 + 1
      kdiff = (regh1 - regl1 + 1) * jdiff
!$omp parallel do reduction(+ : sum)
      do i = kdiff + jdiff + 2, kdiff * (regh2 - regl2) - jdiff - 1
         sum = sum + mask(i) * v0(i) * v1(i)
      end do
!$omp end parallel do
      end
c-----------------------------------------------------------------------
      subroutine hgcg1(
     & r, p, z, x, w, c, mask,
     &     regl0,regh0,regl1,regh1,regl2,regh2,
     & alpha, rho)
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision r(*)
      double precision p(*)
      double precision z(*)
      double precision x(*)
      double precision w(*)
      double precision c(*)
      double precision mask(*)
      double precision alpha, rho
      integer i, jdiff, kdiff
      jdiff = regh0 - regl0 + 1
      kdiff = (regh1 - regl1 + 1) * jdiff
!$omp parallel do reduction(+ : rho)
      do i = kdiff + jdiff + 2, kdiff * (regh2 - regl2) - jdiff - 1
         r(i) = r(i) - alpha * w(i)
         x(i) = x(i) + alpha * p(i)
         z(i) = r(i) * c(i)
         rho = rho + mask(i) * z(i) * r(i)
      end do
!$omp end parallel do
      end
c-----------------------------------------------------------------------
      subroutine hgcg2(
     & p, z,
     &     regl0,regh0,regl1,regh1,regl2,regh2,
     & alpha)
      integer regl0,regh0,regl1,regh1,regl2,regh2
      double precision p(*)
      double precision z(*)
      double precision alpha
      integer i, jdiff, kdiff
      jdiff = regh0 - regl0 + 1
      kdiff = (regh1 - regl1 + 1) * jdiff
!$omp parallel do private(i)
      do i = kdiff + jdiff + 2, kdiff * (regh2 - regl2) - jdiff - 1
         p(i) = alpha * p(i) + z(i)
      end do
!$omp end parallel do
      end
