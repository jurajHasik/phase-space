! 7.4.2013 Juraj Hasik

Program LjClusteringWithMPI

use LJSystem

include 'mpif.h'

!===================================================================================
character charMyId*2
character charMyBetaId*2
character charNumberOfAtoms*3

integer i

Type(LjEnsamble) LjEns
Real*8, allocatable, dimension(:) :: betaArray

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
call rmaset(-6,10,1,(47*myId+1),'nexiste.pa')

write(charMyId,'(I2.2)') myId
open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="unknown")
write(6,'("LjEnsamble - governed by process with Id = ",I2)') myId
close(6)

! ** Initialze LJ Ensamble **
allocate(betaArray(0:(numProcesses-1)))
do i=0, numProcesses-1
  betaArray(i) = 1/(minTemp+dble(numProcesses-1-i)*(maxTemp-minTemp)/dble(numProcesses-1))
end do
call InitLjSystemBeta( LjEns, betaArray, numProcesses, myId, sigma)
call InitLjSystemCoords( numberOfAtoms, LjEns )

! ** Log initial values to separate coressponding file **
open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="old", access="append")
write(6,'("Beta temperature = ",F10.5)') LjEns%staticBetaList(LjEns%myBetaId)
write(6,'("Initial indexes for Neighbours [in Beta Temperature]: ",I2,"  ",I2," [hotter - colder]")') LjEns%betaNeighbours(1), LjEns%betaNeighbours(2)
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
call tryReplicaSwap( LjEns, numProcesses, 0 )
write(charMyBetaId,'(I2.2)') LjEns%myBetaId
open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="old", access="append")
write(6,'("New Beta = ",F10.5)') LjEns%staticBetaList(LjEns%myBetaId)
write(6,'("New indexes for Neighbours [in Beta Temperature]: ",I2," ",I2," ",I2," [hotter - myBetaId - colder]")') LjEns%betaNeighbours(1), LjEns%myBetaId, LjEns%betaNeighbours(2)
close(6)

! **test**
do i=1, 10000
  call sweepOverReplica( numberOfAtoms, sigma, LjEns )
  if (mod(i,1000) .eq. 0) then
    call tryReplicaSwap( LjEns, numProcesses, mod(i,3) )
    open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="old", access="append")
    write(6,'("New Beta = ",F10.5)') LjEns%staticBetaList(LjEns%myBetaId)
    write(6,'("New indexes for Neighbours [in Beta Temperature]: ",I2," ",I2," ",I2," [hotter - myBetaId - colder]")') LjEns%betaNeighbours(1), LjEns%myBetaId, LjEns%betaNeighbours(2)
    close(6)
  endif
end do

!open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="old", access="append")
!write(6,'("New Beta = ",F10.5)') LjEns%staticBetaList(LjEns%myBetaId)
!write(6,'("New indexes for Neighbours [in Beta Temperature]: ",I2," ",I2," ",I2," [hotter - myBetaId - colder]")') LjEns%betaNeighbours(1), LjEns%myBetaId, LjEns%betaNeighbours(2)
!close(6)

call energyOfSystem( sigma, numberOfAtoms, LjEns)
! ** log data after initial equilibriation **
open(6,file="ranGenTest"//charMyId//".dat", form="formatted", status="old", access="append")
write(6,'("Energy after initial equilibriation = ",F10.5)') LjEns%V
write(6,'("Maximal displacement after initial equilibriation = ",F10.5)') LjEns%maxDisplacement
close(6)

call MPI_FINALIZE(ierr)

end

SUBROUTINE tryReplicaSwap ( LjEns, numProcesses, offset )
        
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
      integer numProcesses, offset
      
      integer itag, itagReal
      integer status(MPI_STATUS_SIZE)
      
      !real*8 rmafun
      logical mcCriterionForReplicaSwap
      integer my_ind1, my_ind2, my_ind3
      integer ndest3l, nsend3l, ndest3r, nsend3r, ndest1, NRECV3R, NRECV3L
            
!    *******************************************************************
      call MPI_COMM_RANK(MPI_COMM_WORLD, myId, ierr)
      
      itag=3
      write(*, '("iTag: ",I5)') itag
      itagReal=2
      !itag = 1
      MY_IND1=MOD(LjEns%myBetaId,3)
      MY_IND2=MOD(LjEns%myBetaId+2,3) ! MY_B-1+3
      MY_IND3=MOD(LjEns%myBetaId+1,3) ! MY_B-2+3

      IF(MY_IND1.EQ.offset) THEN ! Processes MY_IND1.
        NDEST3L=LjEns%betaNeighbours(1)
        NSEND3L=-2
        
        IF(LjEns%betaNeighbours(2).LT.numProcesses) THEN
          LjEns%toSend(1)=LjEns%betaNeighbours(1)
          LjEns%toSend(2)=0 ! iact *former energy*
	  LjEns%toSend(3)=LjEns%acceptance
          LjEns%toSendReals(1) = LjEns%V
          
          CALL MPI_SEND(LjEns%toSend,3,MPI_INTEGER,LjEns%betaNeighbours(2),itag,MPI_COMM_WORLD,IERR)
          CALL MPI_SEND(LjEns%toSendReals,1,MPI_REAL8,LjEns%betaNeighbours(2),itagReal,MPI_COMM_WORLD,IERR)
          CALL MPI_RECV(LjEns%toRecieve,2,MPI_INTEGER,LjEns%betaNeighbours(2),itag,MPI_COMM_WORLD,STATUS,IERR)
          
          IF(LjEns%toRecieve(1).NE.-2) THEN
            NSEND3L=LjEns%betaNeighbours(2)
            LjEns%betaNeighbours(1)=LjEns%betaNeighbours(2)
            LjEns%betaNeighbours(2)=LjEns%toRecieve(1)
            LjEns%acceptance=LjEns%toRecieve(2) !**acceptance rate
            LjEns%myBetaId=LjEns%myBetaId+1
          END IF
        
        END IF
        IF(NDEST3L.GE.0) then
	  CALL MPI_SEND(NSEND3L,1,MPI_INTEGER,NDEST3L, itag,MPI_COMM_WORLD,IERR)
	end if
      END IF

      IF(MY_IND2.EQ.offset) THEN ! Processes MY_IND2.
        NDEST3R=LjEns%betaNeighbours(2)
        NSEND3R=-2
        
        IF(LjEns%betaNeighbours(1).GE.0) THEN
          CALL MPI_RECV(LjEns%toRecieve,3,MPI_INTEGER,LjEns%betaNeighbours(1),itag, MPI_COMM_WORLD,STATUS,IERR)
          CALL MPI_RECV(LjEns%toRecieveReals,1,MPI_REAL8,LjEns%betaNeighbours(1),itagReal, MPI_COMM_WORLD,STATUS,IERR)
          
          NDEST1=LjEns%betaNeighbours(1)
          
          IF(mcCriterionForReplicaSwap(LjEns%staticBetaList(LjEns%myBetaId),LjEns%staticBetaList(LjEns%myBetaId-1),LjEns%V,LjEns%toRecieveReals(1))) THEN
          !if(rmafun() .gt. 0.5 ) then
	    write(*,'("SWAP! ",I2)') myId
            LjEns%toSend(1)=LjEns%betaNeighbours(2)
            LjEns%toSend(2)=LjEns%acceptance+1
            LjEns%acceptance=LjEns%toRecieve(3)
            NSEND3R=LjEns%betaNeighbours(1)
            LjEns%betaNeighbours(2)=LjEns%betaNeighbours(1)
            LjEns%betaNeighbours(1)=LjEns%toRecieve(1)
            LjEns%myBetaId=LjEns%myBetaId-1
          ELSE
            LjEns%toSend(1)=-2
          END IF
          
          CALL MPI_SEND(LjEns%toSend,2,MPI_INTEGER,NDEST1,itag, MPI_COMM_WORLD,IERR)
        END IF
        IF(NDEST3R.LT.numProcesses) then
	  CALL MPI_SEND(NSEND3R,1,MPI_INTEGER, NDEST3R,itag,MPI_COMM_WORLD,IERR)
	end if
      END IF

      IF(MY_IND3.EQ.offset) THEN ! Processes MY_IND3.
        IF(LjEns%betaNeighbours(1).GE.0) THEN
          CALL MPI_RECV(NRECV3R,1,MPI_INTEGER,LjEns%betaNeighbours(1), itag,MPI_COMM_WORLD,STATUS,IERR)
          IF(NRECV3R.NE.-2) LjEns%betaNeighbours(1)=NRECV3R
        END IF
        IF(LjEns%betaNeighbours(2).LT.numProcesses) THEN
          CALL MPI_RECV(NRECV3L,1,MPI_INTEGER,LjEns%betaNeighbours(2), itag,MPI_COMM_WORLD,STATUS,IERR)
          IF(NRECV3L.NE.-2) LjEns%betaNeighbours(2)=NRECV3L
        END IF
      END IF

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
	real*8 higherBeta, lowerBeta, lowerEnergy, higherEnergy
	
	real*8 delta

	mcCriterionForReplicaSwap = .false.
	delta = (higherBeta - lowerBeta)*(lowerEnergy - higherEnergy)
	if( rmafun() .lt. exp(-delta)) mcCriterionForReplicaSwap = .true.
	RETURN
end FUNCTION mcCriterionForReplicaSwap

include 'rmaset.f'
include 'rmafun.f'


