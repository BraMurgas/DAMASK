!--------------------------------------------------------------------------------------------------
!> @author Martin Diehl, Max-Planck-Institut für Eisenforschung GmbH
!> @author Pratheek Shanthraj, Max-Planck-Institut für Eisenforschung GmbH
!> @brief material subroutine for thermal source due to plastic dissipation
!> @details to be done
!--------------------------------------------------------------------------------------------------
submodule(phase:thermal) dissipation

  type :: tParameters                                                                               !< container type for internal constitutive parameters
    real(pReal) :: &
      kappa                                                                                         !< TAYLOR-QUINNEY factor
  end type tParameters

  type(tParameters), dimension(:),   allocatable :: param                                           !< containers of constitutive parameters (len Ninstances)


contains


!--------------------------------------------------------------------------------------------------
!> @brief module initialization
!> @details reads in material parameters, allocates arrays, and does sanity checks
!--------------------------------------------------------------------------------------------------
module function dissipation_init(source_length) result(mySources)

  integer, intent(in)                  :: source_length
  logical, dimension(:,:), allocatable :: mySources

  class(tNode), pointer :: &
    phases, &
    phase, &
    sources, thermal, &
    src
  integer :: Ninstances,so,Nconstituents,ph

  print'(/,a)', ' <<<+-  phase:thermal:dissipation init  -+>>>'

  mySources = thermal_active('dissipation',source_length)

  Ninstances = count(mySources)
  print'(a,i2)', ' # instances: ',Ninstances; flush(IO_STDOUT)
  if(Ninstances == 0) return

  phases => config_material%get('phase')
  allocate(param(phases%length))

  do ph = 1, phases%length
    phase => phases%get(ph)
    if(count(mySources(:,ph)) == 0) cycle !ToDo: error if > 1
    thermal => phase%get('thermal')
    sources => thermal%get('source')
    do so = 1, sources%length
      if(mySources(so,ph)) then
        associate(prm  => param(ph))
          src => sources%get(so)

          prm%kappa = src%get_asFloat('kappa')
          Nconstituents = count(material_phaseAt2 == ph)
          call constitutive_allocateState(thermalState(ph)%p(so),Nconstituents,0,0,0)

        end associate
      endif
    enddo
  enddo


end function dissipation_init


!--------------------------------------------------------------------------------------------------
!> @brief Ninstancess dissipation rate
!--------------------------------------------------------------------------------------------------
module subroutine dissipation_getRate(TDot, ph,me)

  integer, intent(in) :: ph, me
  real(pReal),  intent(out) :: &
    TDot


  associate(prm => param(ph))
    TDot = prm%kappa*sum(abs(mech_S(ph,me)*mech_L_p(ph,me)))
  end associate

end subroutine dissipation_getRate

end submodule dissipation
