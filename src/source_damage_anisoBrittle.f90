!--------------------------------------------------------------------------------------------------
!> @author Luv Sharma, Max-Planck-Institut für Eisenforschung GmbH
!> @author Pratheek Shanthraj, Max-Planck-Institut für Eisenforschung GmbH
!> @brief material subroutine incorporating anisotropic brittle damage source mechanism
!> @details to be done
!--------------------------------------------------------------------------------------------------
module source_damage_anisoBrittle
 use prec, only: &
   pReal, &
   pInt

 implicit none
 private
 integer(pInt),                       dimension(:),           allocatable,         public, protected :: &
   source_damage_anisoBrittle_sizePostResults, &                                                                !< cumulative size of post results
   source_damage_anisoBrittle_offset, &                                                                         !< which source is my current source mechanism?
   source_damage_anisoBrittle_instance                                                                          !< instance of source mechanism

 integer(pInt),                       dimension(:,:),         allocatable, target, public  :: &
   source_damage_anisoBrittle_sizePostResult                                                                    !< size of each post result output

 character(len=64),                   dimension(:,:),         allocatable, target, public  :: &
   source_damage_anisoBrittle_output                                                                            !< name of each post result output
   
 integer(pInt),                       dimension(:),           allocatable, target, public  :: &
   source_damage_anisoBrittle_Noutput                                                                           !< number of outputs per instance of this source 

 integer(pInt),                       dimension(:),           allocatable,         private :: &
   source_damage_anisoBrittle_totalNcleavage                                                                    !< total number of cleavage systems
   
 integer(pInt),                       dimension(:,:),         allocatable,         private :: &
   source_damage_anisoBrittle_Ncleavage                                                                         !< number of cleavage systems per family
   
 real(pReal),                         dimension(:,:),         allocatable,         private :: &
   source_damage_anisoBrittle_critDisp, &
   source_damage_anisoBrittle_critLoad

 enum, bind(c) 
   enumerator :: undefined_ID, &
                 damage_drivingforce_ID
 end enum                                                
 
 integer(kind(undefined_ID)),         dimension(:,:),         allocatable,          private :: & 
   source_damage_anisoBrittle_outputID                                                                  !< ID of each post result output


 type, private :: tParameters                                                                       !< container type for internal constitutive parameters
   real(pReal) :: &
     aTol, &
     sdot_0, &
     N
   real(pReal), dimension(:), allocatable :: &
     critDisp, &
     critLoad
   integer(pInt) :: &
     totalNcleavage
   integer(pInt), dimension(:), allocatable :: &
     Ncleavage
 end type tParameters

 type(tParameters), dimension(:), allocatable, private :: param                                     !< containers of constitutive parameters (len Ninstance)


 public :: &
   source_damage_anisoBrittle_init, &
   source_damage_anisoBrittle_dotState, &
   source_damage_anisobrittle_getRateAndItsTangent, &
   source_damage_anisoBrittle_postResults

contains


!--------------------------------------------------------------------------------------------------
!> @brief module initialization
!> @details reads in material parameters, allocates arrays, and does sanity checks
!--------------------------------------------------------------------------------------------------
subroutine source_damage_anisoBrittle_init(fileUnit)
#if defined(__GFORTRAN__) || __INTEL_COMPILER >= 1800
 use, intrinsic :: iso_fortran_env, only: &
   compiler_version, &
   compiler_options
#endif
 use prec, only: &
   pStringLen
 use debug, only: &
   debug_level,&
   debug_constitutive,&
   debug_levelBasic
 use IO, only: &
   IO_read, &
   IO_lc, &
   IO_getTag, &
   IO_isBlank, &
   IO_stringPos, &
   IO_stringValue, &
   IO_floatValue, &
   IO_intValue, &
   IO_warning, &
   IO_error, &
   IO_timeStamp, &
   IO_EOF
 use material, only: &
   material_allocateSourceState, &
   phase_source, &
   phase_Nsources, &
   phase_Noutput, &
   SOURCE_damage_anisoBrittle_label, &
   SOURCE_damage_anisoBrittle_ID, &
   material_phase, &
   sourceState
 use config, only: &
   config_phase, &
   material_Nphase, &
   MATERIAL_partPhase
 use numerics,only: &
   numerics_integrator
 use lattice, only: &
   lattice_maxNcleavageFamily, &
   lattice_NcleavageSystem

 implicit none
 integer(pInt), intent(in) :: fileUnit

 integer(pInt), allocatable, dimension(:) :: chunkPos
 integer(pInt) :: Ninstance,mySize=0_pInt,phase,instance,source,sourceOffset,o
 integer(pInt) :: sizeState, sizeDotState, sizeDeltaState
 integer(pInt) :: NofMyPhase,p   
 integer(pInt) :: Nchunks_CleavageFamilies = 0_pInt, j
 character(len=pStringLen) :: &
   extmsg = ''
 character(len=65536) :: &
   tag  = '', &
   line = ''
 integer(pInt),          dimension(0), parameter :: emptyIntArray    = [integer(pInt)::]

 write(6,'(/,a)')   ' <<<+-  source_'//SOURCE_damage_anisoBrittle_LABEL//' init  -+>>>'
 write(6,'(a15,a)') ' Current time: ',IO_timeStamp()
#include "compilation_info.f90"

 Ninstance = int(count(phase_source == SOURCE_damage_anisoBrittle_ID),pInt)
 if (Ninstance == 0_pInt) return
 
 if (iand(debug_level(debug_constitutive),debug_levelBasic) /= 0_pInt) &
   write(6,'(a16,1x,i5,/)') '# instances:',Ninstance
 
 allocate(source_damage_anisoBrittle_offset(material_Nphase), source=0_pInt)
 allocate(source_damage_anisoBrittle_instance(material_Nphase), source=0_pInt)
 do phase = 1, material_Nphase
   source_damage_anisoBrittle_instance(phase) = count(phase_source(:,1:phase) == source_damage_anisoBrittle_ID)
   do source = 1, phase_Nsources(phase)
     if (phase_source(source,phase) == source_damage_anisoBrittle_ID) &
       source_damage_anisoBrittle_offset(phase) = source
   enddo    
 enddo
   
 allocate(source_damage_anisoBrittle_sizePostResults(Ninstance),                      source=0_pInt)
 allocate(source_damage_anisoBrittle_sizePostResult(maxval(phase_Noutput),Ninstance), source=0_pInt)
 allocate(source_damage_anisoBrittle_output(maxval(phase_Noutput),Ninstance))
          source_damage_anisoBrittle_output = ''
 allocate(source_damage_anisoBrittle_outputID(maxval(phase_Noutput),Ninstance),       source=undefined_ID)
 allocate(source_damage_anisoBrittle_Noutput(Ninstance),                              source=0_pInt)

 allocate(source_damage_anisoBrittle_critDisp(lattice_maxNcleavageFamily,Ninstance),  source=0.0_pReal) 
 allocate(source_damage_anisoBrittle_critLoad(lattice_maxNcleavageFamily,Ninstance),  source=0.0_pReal) 
 allocate(source_damage_anisoBrittle_Ncleavage(lattice_maxNcleavageFamily,Ninstance), source=0_pInt)
 allocate(source_damage_anisoBrittle_totalNcleavage(Ninstance),                       source=0_pInt)

 allocate(param(Ninstance))
 
 do p=1, size(config_phase)
   if (all(phase_source(:,p) /= SOURCE_DAMAGE_ANISOBRITTLE_ID)) cycle
   associate(prm => param(source_damage_anisoBrittle_instance(p)), &
             config => config_phase(p))
             
   prm%aTol      = config%getFloat('anisobrittle_atol',defaultVal = 1.0e-3_pReal)

   prm%N         = config%getFloat('anisobrittle_ratesensitivity')
   prm%sdot_0    = config%getFloat('anisobrittle_sdot0')
   
   ! sanity checks
   if (prm%aTol      < 0.0_pReal) extmsg = trim(extmsg)//' anisobrittle_atol'
   
   if (prm%N        <= 0.0_pReal) extmsg = trim(extmsg)//' anisobrittle_ratesensitivity'
   if (prm%sdot_0   <= 0.0_pReal) extmsg = trim(extmsg)//' anisobrittle_sdot0'
   
   prm%Ncleavage = config%getInts('ncleavage',defaultVal=emptyIntArray)
   
   end associate
   
 enddo

 rewind(fileUnit)
 phase = 0_pInt
 do while (trim(line) /= IO_EOF .and. IO_lc(IO_getTag(line,'<','>')) /= MATERIAL_partPhase)         ! wind forward to <phase>
   line = IO_read(fileUnit)
 enddo
 
 parsingFile: do while (trim(line) /= IO_EOF)                                                       ! read through sections of phase part
   line = IO_read(fileUnit)
   if (IO_isBlank(line)) cycle                                                                      ! skip empty lines
   if (IO_getTag(line,'<','>') /= '') then                                                          ! stop at next part
     line = IO_read(fileUnit, .true.)                                                               ! reset IO_read
     exit                                                                                           
   endif   
   if (IO_getTag(line,'[',']') /= '') then                                                          ! next phase section
     phase = phase + 1_pInt                                                                         ! advance phase section counter
     cycle                                                                                          ! skip to next line
   endif
   if (phase > 0_pInt ) then; if (any(phase_source(:,phase) == SOURCE_damage_anisoBrittle_ID)) then ! do not short-circuit here (.and. with next if statemen). It's not safe in Fortran
     instance = source_damage_anisoBrittle_instance(phase)                                          ! which instance of my damage is present phase
     chunkPos = IO_stringPos(line)
     tag = IO_lc(IO_stringValue(line,chunkPos,1_pInt))                                             ! extract key
     select case(tag)
       case ('(output)')
         select case(IO_lc(IO_stringValue(line,chunkPos,2_pInt)))
           case ('anisobrittle_drivingforce')
             source_damage_anisoBrittle_Noutput(instance) = source_damage_anisoBrittle_Noutput(instance) + 1_pInt
             source_damage_anisoBrittle_outputID(source_damage_anisoBrittle_Noutput(instance),instance) = damage_drivingforce_ID
             source_damage_anisoBrittle_output(source_damage_anisoBrittle_Noutput(instance),instance) = &
                                                       IO_lc(IO_stringValue(line,chunkPos,2_pInt))
          end select
         
       case ('ncleavage')  !
         Nchunks_CleavageFamilies = chunkPos(1) - 1_pInt
         do j = 1_pInt, Nchunks_CleavageFamilies
           source_damage_anisoBrittle_Ncleavage(j,instance) = IO_intValue(line,chunkPos,1_pInt+j)
         enddo

       case ('anisobrittle_criticaldisplacement')
         do j = 1_pInt, Nchunks_CleavageFamilies
           source_damage_anisoBrittle_critDisp(j,instance) = IO_floatValue(line,chunkPos,1_pInt+j)
         enddo

       case ('anisobrittle_criticalload')
         do j = 1_pInt, Nchunks_CleavageFamilies
           source_damage_anisoBrittle_critLoad(j,instance) = IO_floatValue(line,chunkPos,1_pInt+j)
         enddo

     end select
   endif; endif
 enddo parsingFile

!--------------------------------------------------------------------------------------------------
!  sanity checks
 sanityChecks: do phase = 1_pInt, material_Nphase  
   myPhase: if (any(phase_source(:,phase) == SOURCE_damage_anisoBrittle_ID)) then
     instance = source_damage_anisoBrittle_instance(phase)
     source_damage_anisoBrittle_Ncleavage(1:lattice_maxNcleavageFamily,instance) = &
       min(lattice_NcleavageSystem(1:lattice_maxNcleavageFamily,phase),&                            ! limit active cleavage systems per family to min of available and requested
           source_damage_anisoBrittle_Ncleavage(1:lattice_maxNcleavageFamily,instance))
     source_damage_anisoBrittle_totalNcleavage(instance)  = sum(source_damage_anisoBrittle_Ncleavage(:,instance)) ! how many cleavage systems altogether


     if (any(source_damage_anisoBrittle_critDisp(1:Nchunks_CleavageFamilies,instance) < 0.0_pReal)) &
       call IO_error(211_pInt,el=instance,ext_msg='critical_displacement ('//SOURCE_damage_anisoBrittle_LABEL//')')
     if (any(source_damage_anisoBrittle_critLoad(1:Nchunks_CleavageFamilies,instance) < 0.0_pReal)) &
       call IO_error(211_pInt,el=instance,ext_msg='critical_load ('//SOURCE_damage_anisoBrittle_LABEL//')')
 
       
   endif myPhase
 enddo sanityChecks
 
 initializeInstances: do phase = 1_pInt, material_Nphase
   if (any(phase_source(:,phase) == SOURCE_damage_anisoBrittle_ID)) then
     NofMyPhase=count(material_phase==phase)
     instance = source_damage_anisoBrittle_instance(phase)
     sourceOffset = source_damage_anisoBrittle_offset(phase)

!--------------------------------------------------------------------------------------------------
!  Determine size of postResults array
     outputsLoop: do o = 1_pInt,source_damage_anisoBrittle_Noutput(instance)
       select case(source_damage_anisoBrittle_outputID(o,instance))
         case(damage_drivingforce_ID)
           mySize = 1_pInt
       end select
 
       if (mySize > 0_pInt) then  ! any meaningful output found
          source_damage_anisoBrittle_sizePostResult(o,instance) = mySize
          source_damage_anisoBrittle_sizePostResults(instance)  = source_damage_anisoBrittle_sizePostResults(instance) + mySize
       endif
     enddo outputsLoop

     call material_allocateSourceState(phase,sourceOffset,NofMyPhase,1_pInt)
     sourceState(phase)%p(sourceOffset)%sizePostResults = source_damage_anisoBrittle_sizePostResults(instance)
     sourceState(phase)%p(sourceOffset)%aTolState=param(instance)%aTol


   endif
 
 enddo initializeInstances
end subroutine source_damage_anisoBrittle_init

!--------------------------------------------------------------------------------------------------
!> @brief calculates derived quantities from state
!--------------------------------------------------------------------------------------------------
subroutine source_damage_anisoBrittle_dotState(S, ipc, ip, el)
 use math, only: &
   math_mul33xx33
 use material, only: &
   phaseAt, phasememberAt, &
   sourceState, &
   material_homog, &
   damage, &
   damageMapping
 use lattice, only: &
   lattice_Scleavage, &
   lattice_maxNcleavageFamily, &
   lattice_NcleavageSystem

 implicit none
 integer(pInt), intent(in) :: &
   ipc, &                                                                                           !< component-ID of integration point
   ip, &                                                                                            !< integration point
   el                                                                                               !< element
 real(pReal),  intent(in), dimension(3,3) :: &
   S
 integer(pInt) :: &
   phase, &
   constituent, &
   instance, &
   sourceOffset, &
   damageOffset, &
   homog, &
   f, i, index_myFamily
 real(pReal) :: &
   traction_d, traction_t, traction_n, traction_crit

 phase = phaseAt(ipc,ip,el)
 constituent = phasememberAt(ipc,ip,el)
 instance = source_damage_anisoBrittle_instance(phase)
 sourceOffset = source_damage_anisoBrittle_offset(phase)
 homog = material_homog(ip,el)
 damageOffset = damageMapping(homog)%p(ip,el)
 
 sourceState(phase)%p(sourceOffset)%dotState(1,constituent) = 0.0_pReal
 do f = 1_pInt,lattice_maxNcleavageFamily
   index_myFamily = sum(lattice_NcleavageSystem(1:f-1_pInt,phase))                                  ! at which index starts my family
   do i = 1_pInt,source_damage_anisoBrittle_Ncleavage(f,instance)                                   ! process each (active) cleavage system in family
     traction_d    = math_mul33xx33(S,lattice_Scleavage(1:3,1:3,1,index_myFamily+i,phase))
     traction_t    = math_mul33xx33(S,lattice_Scleavage(1:3,1:3,2,index_myFamily+i,phase))
     traction_n    = math_mul33xx33(S,lattice_Scleavage(1:3,1:3,3,index_myFamily+i,phase))
     
     traction_crit = source_damage_anisoBrittle_critLoad(f,instance)* &
                     damage(homog)%p(damageOffset)*damage(homog)%p(damageOffset)
     sourceState(phase)%p(sourceOffset)%dotState(1,constituent) = &
       sourceState(phase)%p(sourceOffset)%dotState(1,constituent) + &
       param(instance)%sdot_0* &
       ((max(0.0_pReal, abs(traction_d) - traction_crit)/traction_crit)**param(instance)%N + &
        (max(0.0_pReal, abs(traction_t) - traction_crit)/traction_crit)**param(instance)%N + &
        (max(0.0_pReal, abs(traction_n) - traction_crit)/traction_crit)**param(instance)%N)/ &
       source_damage_anisoBrittle_critDisp(f,instance)

   enddo
 enddo

end subroutine source_damage_anisoBrittle_dotState

!--------------------------------------------------------------------------------------------------
!> @brief returns local part of nonlocal damage driving force
!--------------------------------------------------------------------------------------------------
subroutine source_damage_anisobrittle_getRateAndItsTangent(localphiDot, dLocalphiDot_dPhi, phi, phase, constituent)
 use material, only: &
   sourceState

 implicit none
 integer(pInt), intent(in) :: &
   phase, &
   constituent
 real(pReal),  intent(in) :: &
   phi
 real(pReal),  intent(out) :: &
   localphiDot, &
   dLocalphiDot_dPhi
 integer(pInt) :: &
   sourceOffset

 sourceOffset = source_damage_anisoBrittle_offset(phase)
 
 localphiDot = 1.0_pReal - &
               sourceState(phase)%p(sourceOffset)%state(1,constituent)*phi
 
 dLocalphiDot_dPhi = -sourceState(phase)%p(sourceOffset)%state(1,constituent)
 
end subroutine source_damage_anisobrittle_getRateAndItsTangent
 
!--------------------------------------------------------------------------------------------------
!> @brief return array of local damage results
!--------------------------------------------------------------------------------------------------
function source_damage_anisoBrittle_postResults(phase, constituent)
 use material, only: &
   sourceState

 implicit none
 integer(pInt), intent(in) :: &
   phase, &
   constituent
 real(pReal), dimension(source_damage_anisoBrittle_sizePostResults( &
                          source_damage_anisoBrittle_instance(phase))) :: &
   source_damage_anisoBrittle_postResults

 integer(pInt) :: &
   instance, sourceOffset, o, c
   
 instance = source_damage_anisoBrittle_instance(phase)
 sourceOffset = source_damage_anisoBrittle_offset(phase)

 c = 0_pInt
 source_damage_anisoBrittle_postResults = 0.0_pReal

 do o = 1_pInt,source_damage_anisoBrittle_Noutput(instance)
    select case(source_damage_anisoBrittle_outputID(o,instance))
      case (damage_drivingforce_ID)
        source_damage_anisoBrittle_postResults(c+1_pInt) = &
          sourceState(phase)%p(sourceOffset)%state(1,constituent)
        c = c + 1_pInt

    end select
 enddo
end function source_damage_anisoBrittle_postResults

end module source_damage_anisoBrittle
