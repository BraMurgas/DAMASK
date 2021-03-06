!--------------------------------------------------------------------------------------------------
!> @author Pratheek Shanthraj, Max-Planck-Institut für Eisenforschung GmbH
!> @brief material subroutine for non-locally evolving damage field
!--------------------------------------------------------------------------------------------------
module damage_nonlocal
  use prec
  use material
  use config
  use YAML_types
  use lattice
  use phase
  use results

  implicit none
  private

  type, private :: tNumerics
    real(pReal) :: &
    charLength                                                                                      !< characteristic length scale for gradient problems
  end type tNumerics

  type(tNumerics), private :: &
    num

  public :: &
    damage_nonlocal_init, &
    damage_nonlocal_getDiffusion

contains

!--------------------------------------------------------------------------------------------------
!> @brief module initialization
!> @details reads in material parameters, allocates arrays, and does sanity checks
!--------------------------------------------------------------------------------------------------
subroutine damage_nonlocal_init

  integer :: Ninstances,Nmaterialpoints,h
  class(tNode), pointer :: &
    num_generic, &
    material_homogenization

  print'(/,a)', ' <<<+-  damage_nonlocal init  -+>>>'; flush(6)

!------------------------------------------------------------------------------------
! read numerics parameter
  num_generic => config_numerics%get('generic',defaultVal= emptyDict)
  num%charLength = num_generic%get_asFloat('charLength',defaultVal=1.0_pReal)

  Ninstances = count(damage_type == DAMAGE_nonlocal_ID)

  material_homogenization => config_material%get('homogenization')
  do h = 1, material_homogenization%length
    if (damage_type(h) /= DAMAGE_NONLOCAL_ID) cycle

    Nmaterialpoints = count(material_homogenizationAt == h)
    damageState_h(h)%sizeState = 1
    allocate(damageState_h(h)%state0   (1,Nmaterialpoints), source=1.0_pReal)
    allocate(damageState_h(h)%state    (1,Nmaterialpoints), source=1.0_pReal)

    damage(h)%p => damageState_h(h)%state(1,:)

  enddo

end subroutine damage_nonlocal_init


!--------------------------------------------------------------------------------------------------
!> @brief returns homogenized non local damage diffusion tensor in reference configuration
!--------------------------------------------------------------------------------------------------
function damage_nonlocal_getDiffusion(ip,el)

  integer, intent(in) :: &
    ip, &                                                                                           !< integration point number
    el                                                                                              !< element number
  real(pReal), dimension(3,3) :: &
    damage_nonlocal_getDiffusion
  integer :: &
    homog, &
    grain

  homog  = material_homogenizationAt(el)
  damage_nonlocal_getDiffusion = 0.0_pReal
  do grain = 1, homogenization_Nconstituents(homog)
    damage_nonlocal_getDiffusion = damage_nonlocal_getDiffusion + &
      crystallite_push33ToRef(grain,ip,el,lattice_D(1:3,1:3,material_phaseAt(grain,el)))
  enddo

  damage_nonlocal_getDiffusion = &
    num%charLength**2*damage_nonlocal_getDiffusion/real(homogenization_Nconstituents(homog),pReal)

end function damage_nonlocal_getDiffusion


end module damage_nonlocal
