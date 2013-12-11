! Copyright 2011-13 Max-Planck-Institut für Eisenforschung GmbH
!
! This file is part of DAMASK,
! the Düsseldorf Advanced MAterial Simulation Kit.
!
! DAMASK is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! DAMASK is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with DAMASK. If not, see <http://www.gnu.org/licenses/>.
!
!--------------------------------------------------------------------------------------------------
! $Id$
!--------------------------------------------------------------------------------------------------
!> @author Franz Roters, Max-Planck-Institut für Eisenforschung GmbH
!> @author Philip Eisenlohr, Max-Planck-Institut für Eisenforschung GmbH
!> @brief material subroutine for purely elastic material
!--------------------------------------------------------------------------------------------------
module constitutive_none
 use prec, only: &
   pReal, &
   pInt
 use lattice, only: &
  LATTICE_undefined_ID
 
 implicit none
 private
 integer(pInt),                       dimension(:),     allocatable,          public, protected :: &
   constitutive_none_sizeDotState, &
   constitutive_none_sizeState, &
   constitutive_none_sizePostResults

 integer(pInt),                       dimension(:,:),   allocatable, target,  public :: &
   constitutive_none_sizePostResult                                                                 !< size of each post result output

 integer(kind(LATTICE_undefined_ID)), dimension(:),     allocatable,          public :: &
   constitutive_none_structureID                                                                !< ID of the lattice structure

 real(pReal),                         dimension(:,:,:), allocatable,          private :: &
   constitutive_none_Cslip_66

 public :: &
   constitutive_none_init, &
   constitutive_none_homogenizedC

contains


!--------------------------------------------------------------------------------------------------
!> @brief module initialization
!> @details reads in material parameters, allocates arrays, and does sanity checks
!--------------------------------------------------------------------------------------------------
subroutine constitutive_none_init(fileUnit)
 use, intrinsic :: iso_fortran_env                                                                  ! to get compiler_version and compiler_options (at least for gfortran 4.6 at the moment)
 use math, only: &
   math_Mandel3333to66, &
   math_Voigt66to3333
 use IO, only: &
   IO_read, &
   IO_lc, &
   IO_getTag, &
   IO_isBlank, &
   IO_stringPos, &
   IO_stringValue, &
   IO_floatValue, &
   IO_error, &
   IO_timeStamp, &
   IO_EOF
 use material
 use debug, only: &
   debug_level, &
   debug_constitutive, &
   debug_levelBasic
 use lattice

 implicit none
 integer(pInt), intent(in) :: fileUnit
 
 integer(pInt), parameter :: MAXNCHUNKS = 7_pInt

 integer(pInt), dimension(1_pInt+2_pInt*MAXNCHUNKS) :: positions
 integer(pInt) :: section = 0_pInt, maxNinstance, i
 character(len=32) :: &
   structure  = ''
 character(len=65536) :: &
   tag  = '', &
   line = ''     
 
 write(6,'(/,a)')   ' <<<+-  constitutive_'//PLASTICITY_NONE_label//' init  -+>>>'
 write(6,'(a)')     ' $Id$'
 write(6,'(a15,a)') ' Current time: ',IO_timeStamp()
#include "compilation_info.f90"
 
 maxNinstance = int(count(phase_plasticity == PLASTICITY_NONE_ID),pInt)
 if (maxNinstance == 0_pInt) return

 if (iand(debug_level(debug_constitutive),debug_levelBasic) /= 0_pInt) &
   write(6,'(a16,1x,i5,/)') '# instances:',maxNinstance
 
 allocate(constitutive_none_sizeDotState(maxNinstance),    source=0_pInt)
 allocate(constitutive_none_sizeState(maxNinstance),       source=0_pInt)
 allocate(constitutive_none_sizePostResults(maxNinstance), source=0_pInt)
 allocate(constitutive_none_structureID(maxNinstance),     source=LATTICE_undefined_ID)
 allocate(constitutive_none_Cslip_66(6,6,maxNinstance),    source=0.0_pReal)
 
 rewind(fileUnit)
 do while (trim(line) /= IO_EOF .and. IO_lc(IO_getTag(line,'<','>')) /= 'phase')                    ! wind forward to <phase>
   line = IO_read(fileUnit)
 enddo
 
 do while (trim(line) /= IO_EOF)                                                                    ! read through sections of phase part
   line = IO_read(fileUnit)
   if (IO_isBlank(line)) cycle                                                                      ! skip empty lines
   if (IO_getTag(line,'<','>') /= '') then                                                          ! stop at next part
     line = IO_read(fileUnit, .true.)                                                               ! reset IO_read
     exit                                                                                           
   endif
   if (IO_getTag(line,'[',']') /= '') then                                                          ! next section
     section = section + 1_pInt                                                                     ! advance section counter
     cycle
   endif
   if (section > 0_pInt ) then                                                                      ! do not short-circuit here (.and. with next if-statement). It's not safe in Fortran
     if (phase_plasticity(section) == PLASTICITY_NONE_ID) then                                      ! one of my sections
       i = phase_plasticityInstance(section)                                                        ! which instance of my plasticity is present phase
       positions = IO_stringPos(line,MAXNCHUNKS)
       tag = IO_lc(IO_stringValue(line,positions,1_pInt))                                           ! extract key
       select case(tag)
         case ('plasticity','elasticity')
           cycle
         case ('lattice_structure')
           structure = IO_lc(IO_stringValue(line,positions,2_pInt))
           select case(structure(1:3))
             case(LATTICE_iso_label)
               constitutive_none_structureID(i) = LATTICE_iso_ID
             case(LATTICE_fcc_label)
               constitutive_none_structureID(i) = LATTICE_fcc_ID
             case(LATTICE_bcc_label)
               constitutive_none_structureID(i) = LATTICE_bcc_ID
             case(LATTICE_hex_label)
               constitutive_none_structureID(i) = LATTICE_hex_ID
             case(LATTICE_ort_label)
               constitutive_none_structureID(i) = LATTICE_ort_ID
           end select
         case ('c11')
           constitutive_none_Cslip_66(1,1,i) = IO_floatValue(line,positions,2_pInt)
         case ('c12')
           constitutive_none_Cslip_66(1,2,i) = IO_floatValue(line,positions,2_pInt)
         case ('c13')
           constitutive_none_Cslip_66(1,3,i) = IO_floatValue(line,positions,2_pInt)
         case ('c22')
           constitutive_none_Cslip_66(2,2,i) = IO_floatValue(line,positions,2_pInt)
         case ('c23')
           constitutive_none_Cslip_66(2,3,i) = IO_floatValue(line,positions,2_pInt)
         case ('c33')
           constitutive_none_Cslip_66(3,3,i) = IO_floatValue(line,positions,2_pInt)
         case ('c44')
           constitutive_none_Cslip_66(4,4,i) = IO_floatValue(line,positions,2_pInt)
         case ('c55')
           constitutive_none_Cslip_66(5,5,i) = IO_floatValue(line,positions,2_pInt)
         case ('c66')
           constitutive_none_Cslip_66(6,6,i) = IO_floatValue(line,positions,2_pInt)
         case default
           call IO_error(210_pInt,ext_msg=trim(tag)//' ('//PLASTICITY_NONE_label//')')
       end select
     endif
   endif
 enddo

 instancesLoop: do i = 1_pInt,maxNinstance
   constitutive_none_sizeDotState(i)    = 1_pInt
   constitutive_none_sizeState(i)       = 1_pInt

   constitutive_none_Cslip_66(1:6,1:6,i) = lattice_symmetrizeC66(constitutive_none_structureID(i),&
                                                           constitutive_none_Cslip_66(1:6,1:6,i))
   constitutive_none_Cslip_66(1:6,1:6,i) = &
     math_Mandel3333to66(math_Voigt66to3333(constitutive_none_Cslip_66(1:6,1:6,i)))

 enddo instancesLoop

end subroutine constitutive_none_init


!--------------------------------------------------------------------------------------------------
!> @brief returns the homogenized elasticity matrix
!--------------------------------------------------------------------------------------------------
pure function constitutive_none_homogenizedC(ipc,ip,el)
 use prec, only: &
   p_vec
 use mesh, only: &
   mesh_NcpElems, &
   mesh_maxNips
 use material, only: &
  homogenization_maxNgrains, &
  material_phase, &
  phase_plasticityInstance
 
 implicit none
 real(pReal), dimension(6,6) :: &
   constitutive_none_homogenizedC
 integer(pInt), intent(in) :: &
   ipc, &                                                                                           !< component-ID of integration point
   ip, &                                                                                            !< integration point
   el                                                                                               !< element

 constitutive_none_homogenizedC = constitutive_none_Cslip_66(1:6,1:6,&
                                              phase_plasticityInstance(material_phase(ipc,ip,el)))

end function constitutive_none_homogenizedC

end module constitutive_none
