!--------------------------------------------------------------------------------------------------
!> @author Martin Diehl, Max-Planck-Institut für Eisenforschung GmbH
!> @author Franz Roters, Max-Planck-Institut für Eisenforschung GmbH
!> @author Philip Eisenlohr, Max-Planck-Institut für Eisenforschung GmbH
!> @brief Isostrain (full constraint Taylor assuption) homogenization scheme
!--------------------------------------------------------------------------------------------------
module homogenization_isostrain
 use prec, only: &
   pInt
 
 implicit none
 private
 enum, bind(c) 
   enumerator :: parallel_ID, &
                 average_ID
 end enum

 type, private :: tParameters                                                                       !< container type for internal constitutive parameters
   integer(pInt) :: &
     Nconstituents
   integer(kind(average_ID)) :: &
     mapping
 end type

 type(tParameters), dimension(:), allocatable, private :: param                                     !< containers of constitutive parameters (len Ninstance)

 public :: &
   homogenization_isostrain_init, &
   homogenization_isostrain_partitionDeformation, &
   homogenization_isostrain_averageStressAndItsTangent

contains

!--------------------------------------------------------------------------------------------------
!> @brief allocates all neccessary fields, reads information from material configuration file
!--------------------------------------------------------------------------------------------------
subroutine homogenization_isostrain_init()
#if defined(__GFORTRAN__) || __INTEL_COMPILER >= 1800
 use, intrinsic :: iso_fortran_env, only: &
   compiler_version, &
   compiler_options
#endif
 use debug, only: &
   debug_HOMOGENIZATION, &
   debug_level, &
   debug_levelBasic
 use IO, only: &
   IO_timeStamp, &
   IO_error
 use material, only: &
   homogenization_type, &
   material_homog, &
   homogState, &
   HOMOGENIZATION_ISOSTRAIN_ID, &
   HOMOGENIZATION_ISOSTRAIN_LABEL, &
   homogenization_typeInstance
 use config, only: &
   config_homogenization
 
 implicit none
 integer(pInt) :: &
   h
 integer :: &
   Ninstance
 integer :: &
   NofMyHomog                                                                                       ! no pInt (stores a system dependen value from 'count'
 character(len=65536) :: &
   tag  = ''
 type(tParameters) :: prm
 
 write(6,'(/,a)')   ' <<<+-  homogenization_'//HOMOGENIZATION_ISOSTRAIN_label//' init  -+>>>'
 write(6,'(a15,a)') ' Current time: ',IO_timeStamp()
#include "compilation_info.f90"

 Ninstance = count(homogenization_type == HOMOGENIZATION_ISOSTRAIN_ID)
 if (Ninstance == 0) return
 
 if (iand(debug_level(debug_HOMOGENIZATION),debug_levelBasic) /= 0_pInt) &
   write(6,'(a16,1x,i5,/)') '# instances:',Ninstance

 allocate(param(Ninstance))                                                                         ! one container of parameters per instance

 do h = 1_pInt, size(homogenization_type)
   if (homogenization_type(h) /= HOMOGENIZATION_ISOSTRAIN_ID) cycle
   associate(prm => param(homogenization_typeInstance(h)))
  
   prm%Nconstituents = config_homogenization(h)%getInt('nconstituents')
   tag = 'sum'
   tag = config_homogenization(h)%getString('mapping',defaultVal = tag)
   select case(trim(tag))
     case ('sum')
       prm%mapping = parallel_ID
     case ('avg')
       prm%mapping = average_ID
     case default
       call IO_error(211_pInt,ext_msg=trim(tag)//' ('//HOMOGENIZATION_isostrain_label//')')
   end select

   NofMyHomog = count(material_homog == h)

   homogState(h)%sizeState       = 0_pInt
   homogState(h)%sizePostResults = 0_pInt
   allocate(homogState(h)%state0   (0_pInt,NofMyHomog))
   allocate(homogState(h)%subState0(0_pInt,NofMyHomog))
   allocate(homogState(h)%state    (0_pInt,NofMyHomog))
   end associate

 enddo

end subroutine homogenization_isostrain_init


!--------------------------------------------------------------------------------------------------
!> @brief partitions the deformation gradient onto the constituents
!--------------------------------------------------------------------------------------------------
subroutine homogenization_isostrain_partitionDeformation(F,avgF,instance)
 use prec, only: &
   pReal
 use material, only: &
   homogenization_maxNgrains
 
 implicit none
 real(pReal),   dimension (3,3,homogenization_maxNgrains), intent(out) :: F                         !< partioned def grad per grain
 real(pReal),   dimension (3,3),                           intent(in)  :: avgF                      !< my average def grad
 integer(pInt),                                            intent(in)  :: instance 
 type(tParameters) :: &
   prm

 associate(prm => param(instance))
 F(1:3,1:3,1:prm%Nconstituents) = spread(avgF,3,prm%Nconstituents)
 if (homogenization_maxNgrains > prm%Nconstituents) &
   F(1:3,1:3,prm%Nconstituents+1_pInt:homogenization_maxNgrains) = 0.0_pReal
 end associate

end subroutine homogenization_isostrain_partitionDeformation


!--------------------------------------------------------------------------------------------------
!> @brief derive average stress and stiffness from constituent quantities 
!--------------------------------------------------------------------------------------------------
subroutine homogenization_isostrain_averageStressAndItsTangent(avgP,dAvgPdAvgF,P,dPdF,instance)
 use prec, only: &
   pReal
 use material, only: &
   homogenization_maxNgrains
 
 implicit none
 real(pReal),   dimension (3,3),                               intent(out) :: avgP                  !< average stress at material point
 real(pReal),   dimension (3,3,3,3),                           intent(out) :: dAvgPdAvgF            !< average stiffness at material point
 real(pReal),   dimension (3,3,homogenization_maxNgrains),     intent(in)  :: P                     !< array of current grain stresses
 real(pReal),   dimension (3,3,3,3,homogenization_maxNgrains), intent(in)  :: dPdF                  !< array of current grain stiffnesses
 integer(pInt),                                                intent(in)  :: instance 
 type(tParameters) :: &
   prm

 associate(prm => param(instance))
 select case (prm%mapping)
   case (parallel_ID)
     avgP       = sum(P,3)
     dAvgPdAvgF = sum(dPdF,5)
   case (average_ID)
     avgP       = sum(P,3)   /real(prm%Nconstituents,pReal)
     dAvgPdAvgF = sum(dPdF,5)/real(prm%Nconstituents,pReal)
 end select
 end associate

end subroutine homogenization_isostrain_averageStressAndItsTangent

end module homogenization_isostrain
