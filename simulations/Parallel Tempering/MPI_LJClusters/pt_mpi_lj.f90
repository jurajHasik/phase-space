! 7.4.2013 Juraj Hasik

Program LjClusteringWithMPI

use LJSystem

include 'mpif.h'

!===================================================================================
character charMyId*2
character charNumberOfAtoms*3

integer i

REAL*8 DRMAX

Type(LjEnsamble) LjEns
Real*8 initialBeta

! ** Diagnostic variables **



!       John A. White "Lennard-Jones as a model for argon and test of extended renormalization group calculations", 
!	Journal of Chemical Physics 111 pp. 9352-9356 (1999)
!	Parameter Set #4
!	epsilon/K_b = 125.7 K
Real*8, parameter :: sigma = 3.4345 !Ang

! Minimum temperature reached during simulation in LJ units
REAL*8, Parameter :: minTemp = 0.039777
REAL*8, Parameter :: maxTemp = 0.318218
Integer, parameter :: numberOfAtoms = 55
Integer, parameter :: initialEquilibriation = 5000 

REAL*8, PARAMETER :: PI = 3.1415927
!===================================================================================

call MPI_INIT(ierr)
call MPI_COMM_RANK(MPI_COMM_WORLD, myId, ierr)
call MPI_COMM_SIZE(MPI_COMM_WORLD, numProcesses, ierr)

! ** Log info about current run **
if(myId.eq.0) then
  write(charNumberOfAtoms,'(I3.3)') numberOfAtoms
  open(7,file="ptMpi"//charNumberOfAtoms//".log", form="formatted", status="unknown")
  write(7,'("Parallel Tampering with Mpi")')
  write(7,'("Number of processes: ",I2)') numProcesses
  write(7,'("Number of Atoms: ",I3)') numberOfAtoms
  write(7,'("Temperature range: ",F10.6," - ",F10.6," [in LJ units]")') minTemp, maxTemp
end if

! ** Initialize PRNG **
call rmaset(-6,10,1,myId,'nexiste.pa')

write(charMyId,'(I2.2)') myId
open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="unknown")
write(6,'("LjEnsamble - governed by process with Id = ",I2)') myId
close(6)

! ** Initialze LJ Ensamble **
initialBeta = 1/(minTemp+dble(myId)*(maxTemp-minTemp)/dble(numProcesses))
call InitLjSystemBeta( LjEns, initialBeta, (myId-1), myId, (myId+1), sigma)
call InitLjSystemCoords( numberOfAtoms, LjEns )

! ** Log initial values to separate coressponding file **
open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="old", access="append")
write(6,'("Beta temperature = ",F10.5)') LjEns%Beta
write(6,'("Initial indexes by Beta Temperature: ",I2,"  ",I2,"  ",I2," [colder - my index - hotter]")') LjEns%higherBetaId, LjEns%myBetaId, LjEns%lowerBetaId
write(6,'("Initial Coordinates for N = ",I3," atoms")') numberOfAtoms
  do i=1, numberOfAtoms
    write(6,'(3F10.5)') LjEns%X(i), LjEns%Y(i), LjEns%Z(i)
  end do
close(6)

! ** equilibriate after initialization and set optimal maximalDisplacement for trial move**
do i=1, initialEquilibriation
  call sweepOverReplica( numberOfAtoms, sigma, LjEns )
end do

call energyOfSystem( sigma, numberOfAtoms, LjEns)
! ** log data after initial equilibriation **
open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="old", access="append")
write(6,'("Energy after initial equilibriation = ",F10.5)') LjEns%V
write(6,'("Maximal displacement after initial equilibriation = ",F10.5)') LjEns%maxDisplacement
close(6)

! ** 
call tryReplicaSwap( LjEns, myId, numProcesses )
open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="old", access="append")
write(6,'("Extended Neighbour list: ",I2," ",I2," ",I2)') LjEns%neighbourList(1), LjEns%neighbourList(2), LjEns%neighbourList(3) 
write(6,'("Energy and Beta of higherBeta LjSystem: ",F10.5," ",F10.5)' ) LjEns%higherBetaNeighbourStats(1), LjEns%higherBetaNeighbourStats(2)
close(6)

call MPI_FINALIZE(ierr)

end

SUBROUTINE tryReplicaSwap ( LjEns, myId, numProcesses )
        
!    *******************************************************************
!    ** Attepmts an exchange of Beta temperatures                     **
!    **                                                               **
!    ** PRINCIPAL VARIABLES:                                          **
!    **                                                               **
!    **								      **
!    *******************************************************************
      use LJSystem
      include 'mpif.h'
      
      Type(LjEnsamble) LjEns
      integer myId, numProcesses
      
      integer itag
      integer, dimension(3) :: toSend, toRecieve
      real*8, dimension(4) :: toSendReals, toRecieveReals
      integer status(MPI_STATUS_SIZE)
      
      logical swapSuccess
      
!    *******************************************************************

!	** Create local list of neighbours [2 colder, this process, 1 hotter]
	LjEns%neighbourList(2) = LjEns%higherBetaId
	LjEns%neighbourList(3) = LjEns%lowerBetaId
	
	itag = 1
	if (LjEns%myBetaId .ne. (numProcesses-1) ) then
	  toSend(1) = LjEns%higherBetaId 
	  call MPI_SEND(toSend, 1, MPI_INTEGER, LjEns%lowerBetaId, itag, MPI_COMM_WORLD, ierr)
	endif
	if (LjEns%myBetaId .ne. 0) then
	  call MPI_RECV(toRecieve, 1, MPI_INTEGER, LjEns%higherBetaId, itag, MPI_COMM_WORLD, status, ierr)
	  LjEns%neighbourList(1) = toRecieve(1)
	endif
	
!	** Send energy and beta to process with lowerBeta ["hotter"] ** 
	itag = 2
	if (LjEns%myBetaId .ne. (numProcesses-1) ) then
	  toSendReals(1) = LjEns%V
	  toSendReals(2) = LjEns%beta
	  toSendReals(3) = LjEns%maxDisplacement
	  call MPI_SEND(toSendReals, 3, MPI_REAL8, LjEns%lowerBetaId, itag, MPI_COMM_WORLD, ierr)
	endif
	if (LjEns%myBetaId .ne. 0) then
	  call MPI_RECV(toRecieveReals, 3, MPI_REAL8, LjEns%higherBetaId, itag, MPI_COMM_WORLD, status, ierr)
	  LjEns%higherBetaNeighbourStats(1) = toRecieveReals(1)
	  LjEns%higherBetaNeighbourStats(2) = toRecieveReals(2)
	  LjEns%higherBetaNeighbourStats(3) = toRecieveReals(3)
        endif
        
        swapSuccess = .false.
!       ** Attempt swapping the replicas [called by "hotter" replica] **
	if(LjEns%myBetaId .ne. 0) then
	  swapSuccess = mcCriterionForReplicaSwap(LjEns%higherBetaNeighbourStats(2), LjEns%beta, LjEns%higherBetaNeighbourStats(1), LjEns%V)
        endif
        
        if( swapSuccess ) then
	 ! ** Send my values to "colder" replica ** 
	  toSendReals(1) = LjEns%V
	  toSendReals(2) = LjEns%beta
	  toSendReals(3) = LjEns%maxDisplacement
	  call MPI_SEND(toSendReals, 3, MPI_REAL8, LjEns%higherBetaId, itag, MPI_COMM_WORLD, ierr)
	  if (myId .eq. )
	  call MPI_RECV(toRecieveReals, 3, MPI_REAL8, LjEns%lowerBetaId, itag, MPI_COMM_WORLD, status, ierr)
	  LjEns%V = toRecieveReals(1)
	  LjEns%beta = toRecieveReals(2)
	  LjEns%maxDisplacement = toRecieveReals(3)
        endif
        
        RETURN
END subroutine tryReplicaSwap

FUNCTION mcCriterionForReplicaSwap( higherBeta, lowerBeta, lowerEnergy, higherEnergy ) 

!    *******************************************************************
!    ** Metropolis criterion for accepting the replica swap move      **
!    **                                                               **
!    ** PRINCIPAL VARIABLES:                                          **
!    **                                                               **
!    **								      **
!    *******************************************************************
	real*8 delta

	mcCriterionForReplicaSwap = .false.
	delta = (higherBeta - lowerBeta)*(lowerEnergy - higherEnergy)
	if( rmafun() .lt. exp(-delta)) mcCriterionForReplicaSwap = .true.
	RETURN
end FUNCTION mcCriterionForReplicaSwap

include 'rmaset.f'
include 'rmafun.f'


