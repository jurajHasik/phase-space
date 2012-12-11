! -*-fortran-*-

! *****************************************************************************
! ** FICHE F.11.  CONSTANT-NVT MONTE CARLO FOR LENNARD JONES ATOMS           **
! ** This FORTRAN code is intended to illustrate points made in the text.    **
! ** To our knowledge it works correctly.  However it is the responsibility  **
! ** of the user to test it, if it is to be used in a research application.  **
! *****************************************************************************

! Modified by J.Hasik, Dec 2012
! Optimization by Simulated Annealing, S Kirckpatrick, C. D. Gellaat; M.P. Vecchi
! Science, New Series, Vol. 220, No. 4598. (May 13, 1983)

! *****************************************************************************
! **                                                                         **
! **  Modified by A.Kuronen, Feb 1997:                                       **
! **                                                                         **
! **  Coordinates are now in common area COORDS which is in file 'common.f'. **
! **      This file is read in all subroutines using command 'include'.      **
! **      If your FORTRAN compiler does not have this command the file       **
! **      can be included by hand.                                           **
! **  Configuration file read as formatted (ascii) data.                     **
! **  Number of particles read from configuration file.                      **
! **  Added input parameter NEQU. This is the number of MC cycles simulated  **
! **      before we start to calculate averages.                             **
! **  Added calculation of order parameter. K-vector is set to 2pi/a(111).   **
! **  The wanted acceptance ratio is now read in (RATIOX).                   **
! **                                                                         **
! *****************************************************************************



        PROGRAM MCNVT


!    *******************************************************************
!    ** MONTE CARLO SIMULATION PROGRAM IN THE CONSTANT-NVT ENSEMBLE.  **
!    **                                                               **
!    ** THIS PROGRAM TAKES A CONFIGURATION OF LENNARD JONES ATOMS     **
!    ** AND PERFORMS A CONVENTIONAL NVT MC SIMULATION. THE BOX IS OF  **
!    ** UNIT LENGTH, -0.5 TO +0.5 AND THERE ARE NO LOOKUP TABLES.     **
!    **                                                               **
!    ** PRINCIPAL VARIABLES:                                          **
!    **                                                               **
!    ** INTEGER N                   NUMBER OF MOLECULES               **
!    ** INTEGER NSTEP               MAXIMUM NUMBER OF CYCLES /unused/ **
!    ** INTEGER NEQU                NUMBER OF EQUILIBRATION CYCLES    **
!    ** REAL    RX(N),RY(N),RZ(N)   POSITIONS                         **
!    ** REAL    DENS                REDUCED DENSITY                   **
!    ** REAL    TEMP                REDUCED TEMPERATURE               **
!    ** REAL    SIGMA               REDUCED LJ DIAMETER               **
!    ** REAL    RMIN                MINIMUM REDUCED PAIR SEPARATION   **
!    ** REAL    RCUT                REDUCED CUTOFF DISTANCE           **
!    ** REAL    DRMAX               REDUCED MAXIMUM DISPLACEMENT      **
!    ** REAL    V                   THE POTENTIAL ENERGY              **
!    ** REAL    W                   THE VIRIAL                        **
!    ** REAL    PRES                THE PRESSURE                      **
!    **                                                               **
!    ** USAGE:                                                        **
!    **                                                               **
!    ** THE PROGRAM TAKES IN A CONFIGURATION OF ATOMS                 **
!    ** AND RUNS A MONTE CARLO SIMULATION AT THE GIVEN TEMPERATURE    **
!    ** FOR THE SPECIFIED NUMBER OF CYCLES.                           **
!    **                                                               **
!    ** UNITS:                                                        **
!    **                                                               **
!    ** THE PROGRAM USES LENNARD-JONES UNITS FOR USER INPUT AND       **
!    ** OUTPUT BUT CONDUCTS THE SIMULATION IN A BOX OF UNIT LENGTH.   **
!    ** FOR EXAMPLE, FOR A BOXLENGTH L, AND LENNARD-JONES PARAMETERS  **
!    ** EPSILON AND SIGMA, THE UNITS ARE:                             **
!    **                                                               **
!    **     PROPERTY       LJ  UNITS            PROGRAM UNITS         **
!    **                                                               **
!    **     TEMP           EPSILON/K            EPSILON/K             **
!    **     PRES           EPSILON/SIGMA**3     EPSILON/L**3          **
!    **     V              EPSILON              EPSILON               **
!    **     DENS           1/SIGMA**3           1/L**3                **
!    **                                                               **
!    ** ROUTINES REFERENCED (AND INCLUDED IN THIS FILE):              **
!    **                                                               **
!    ** SUBROUTINE SUMUP ( RCUT, RMIN, SIGMA, OVRLAP, V, W )          **
!    **    CALCULATES THE TOTAL POTENTIAL ENERGY FOR A CONFIGURATION  **
!    ** SUBROUTINE ENERGY ( RXI, RYI, RZI, I, RCUT, SIGMA, V, W )     **
!    **    CALCULATES THE POTENTIAL ENERGY OF ATOM I WITH ALL THE     **
!    **    OTHER ATOMS IN THE LIQUID                                  **
!    ** SUBROUTINE READCN (CNFILE )                                   **
!    **    READS IN A CONFIGURATION                                   **
!    ** SUBROUTINE WRITCN ( CNFILE )                                  **
!    **    WRITES OUT A CONFIGURATION                                 **
!    ** REAL FUNCTION RANF ( SEED )                                   **
!    **    RETURNS A UNIFORM RANDOM NUMBER BETWEEN ZERO AND ONE       **SIGMA
!    ** SUBROUTINE ORDER ( KX, KY, KZ, RHO )                          **
!    **    RETURNS THE ORDER PARAMETER RHO FOR K-VECTOR (KX,KY,KZ)    **
!    **                                                               **
!    *******************************************************************

        include 'common.f'

        REAL*8        DRMAX, DENS, TEMP, DENSLJ, SIGMA, RMIN, RCUT, BETA
        REAL*8        ACM, ACATMA, PI, RATIO
        REAL*8        ACM1, DUMM, ZBQLU01
        REAL*8        V, VNEW, VOLD, VEND, VN, DELTV, DELTVB, VS
        REAL*8        W, WEND, WNEW, WOLD, PRES, DELTW, WS, PS
        REAL*8        VLRC, VLRC6, VLRC12, WLRC, WLRC6, WLRC12
        REAL*8        RXIOLD, RYIOLD, RZIOLD, RXINEW, RYINEW, RZINEW
        REAL*8        AVV, AVP, AVW, ACV, ACP, ACVSQ, ACPSQ, FLV, FLP
        REAL*8        KLATX, KLATY, KLATZ, PARAM, AVPARA, AVPASQ, FPAR, PARS
        INTEGER     NPARAM
        INTEGER     SEED

	INTEGER     TCACC, TCATM
!		     TCACC - number of accepted moves for current temperature
!		     TCACC - number of attempted moves for current temperature
        INTEGER     STEP, I, NSTEP, IPRINT, ISAVE
        LOGICAL     OVRLAP
        CHARACTER   TITLE*80, CNFILE*30
        CHARACTER   SAVEFILE*30
        
        PARAMETER ( PI = 3.1415927 )
	PARAMETER ( DUMM = 1.0 )

!       ****************************************************************

!    ** READ INPUT DATA **

        WRITE(*,'(//,'' **** PROGRAM MCLJ ****                   ''/)')
        WRITE(*,'('' CONSTANT-NVT MONTE CARLO PROGRAM            '' )')
        WRITE(*,'('' FOR LENNARD JONES ATOMS                      '')')

        WRITE(*,'('' ENTER THE RUN TITLE                          '')')
        READ (*,'(A)') TITLE
        WRITE(*,'('' ENTER NUMBER OF EQUILIBRATION CYCLES         '')')
        READ (*,*) NEQU
        WRITE(*,'('' ENTER NUMBER OF STEPS BETWEEN OUTPUT LINES   '')')
        READ (*,*) IPRINT
        WRITE(*,'('' ENTER NUMBER OF STEPS BETWEEN DATA SAVES     '')')
        READ (*,*) ISAVE
        WRITE(*,'('' ENTER THE CONFIGURATION FILE NAME            '')')
        READ (*,'(A)') CNFILE
        WRITE(*,'('' ENTER THE SAVE FILE NAME                     '')')
        READ (*,'(A)') SAVEFILE
        WRITE(*,'('' ENTER THE FOLLOWING IN LENNARD-JONES UNITS '',/)')  
!	Argon
!	3,76 [angstrom] - minimal pair separation in liquid at zero pressure     
!	5,31 [angstrom] - lattice constant at 4K
!       1,11 [sigma] - nearest neighbor distance 
!	fcc - Crystal configuration at equilibrium
!       Kittel, Introduction to Solid State physics, 8th edition  
	WRITE(*,'('' ENTER THE DENSITY                        '')')
        READ (*,*) DENS
        WRITE(*,'('' ENTER THE TEMPERATURE                        '')')
        READ (*,*) TEMP
        WRITE(*,'('' RANDOM NUMBER GENERATOR SEED                 '')')
        READ (*,*) SEED

!    ** WRITE INPUT DATA **

        WRITE(*,'(       //1X                    ,A     )') TITLE
        WRITE(*,'('' NUMBER OF ATOMS           '',I10   )') N
        WRITE(*,'('' OUTPUT FREQUENCY          '',I10   )') IPRINT
        WRITE(*,'('' SAVE FREQUENCY            '',I10   )') ISAVE
        WRITE(*,'('' RANDOM NUMBER GEN. SEED   '',I10   )') SEED
        WRITE(*,'('' CONFIGURATION FILE  NAME  '',A     )') CNFILE
        WRITE(*,'('' TEMPERATURE               '',F10.4 )') TEMP
        WRITE(*,'('' DENSITY                   '',F10.4 )') DENS

!    ** READ INITIAL CONFIGURATION **

        CALL READCN ( CNFILE )

!    ** CONVERT INPUT DATA TO PROGRAM UNITS **

!       John A. White "Lennard-Jones as a model for argon and test of extended renormalization group calculations", 
!	Journal of Chemical Physics 111 pp. 9352-9356 (1999)
!	Parameter Set #4
!	epsilon/K_b = 125.7 K
!	sigma = 3,4345 Ang	

        BETA   = 1.0 / TEMP
        SIGMA  = ( DENS / REAL ( N ) ) ** ( 1.0 / 3.0 )
        !RMIN - Kittel, Introduction to Solid State Physics
        RMIN   = 0.707 * SIGMA
        DRMAX  = 0.15 * SIGMA
        DENSLJ = DENS
        DENS   = DENS / ( SIGMA ** 3 )

!    ** ZERO ACCUMULATORS **

        ACV    = 0.0
        ACVSQ  = 0.0
        ACP    = 0.0
        ACPSQ  = 0.0
        FLV    = 0.0
        FLP    = 0.0
        ACM    = 0.0
        ACMM1  = 0.0
        ACATMA = 0.0

!    ** ORDER PARAMETER ** K-vector corresponds to 2pi/a*(111) 

        KLATX=25.13274132
        KLATY=25.13274132
        KLATZ=25.13274132
        AVPARA=0.0
        AVPASQ=0.0
        NPARAM=0
        FPAR=0.0

!    ** WRITE OUT SOME USEFUL INFORMATION **

        WRITE(*,'('' SIGMA/BOX              =  '',F10.4)')  SIGMA
        WRITE(*,'('' RMIN/BOX               =  '',F10.4)')  RMIN

!    ** CALCULATE INITIAL ENERGY AND CHECK FOR OVERLAPS **

        CALL SUMUP ( RMIN, SIGMA, OVRLAP, V, W )

        IF ( OVRLAP ) STOP ' OVERLAP IN INITIAL CONFIGURATION '

        CALL ORDER ( KLATX, KLATY, KLATZ, PARS )
        
	VS = ( V ) / REAL ( N )
        WS = ( W ) / REAL ( N )
        PS = DENS * TEMP + W
        PS = PS * SIGMA ** 3

        WRITE(*,'('' INITIAL V              =  '', F10.4 )' ) VS
        WRITE(*,'('' INITIAL W              =  '', F10.4 )' ) WS
        WRITE(*,'('' INITIAL P              =  '', F10.4 )' ) PS
        WRITE(*,'('' INITIAL ORDER PARM.    =  '', F10.4 )' ) PARS

        WRITE(*,'(//'' START OF MARKOV CHAIN               ''//)')
        WRITE(*,'(''    STEP    NMOVE     RATIO       V/N  '',&
        '' P   ORDERPARAM''/)')
        
!    ** INITIALIZE RANDOM NUMBER GENERATOR **        
	CALL ZBQLINI ( SEED )

!    *******************************************************************
!    ** LOOPS OVER ALL CYCLES AND ALL MOLECULES                       **
!    *******************************************************************

	OPEN ( UNIT = 11, FILE = SAVEFILE, STATUS = 'UNKNOWN' )

        DO STEP = 1, NEQU

           DO I = 1, N

              RXIOLD = RX(I)
              RYIOLD = RY(I)
              RZIOLD = RZ(I)

!          ** CALCULATE THE ENERGY OF I IN THE OLD CONFIGURATION **

              CALL ENERGY(RXIOLD,RYIOLD,RZIOLD,I,SIGMA,VOLD,WOLD)

!          ** MOVE I AND PICKUP THE CENTRAL IMAGE **

              RXINEW = RXIOLD + ( 2.0 * ZBQLU01(DUMM) - 1.0 ) * DRMAX
              RYINEW = RYIOLD + ( 2.0 * ZBQLU01(DUMM) - 1.0 ) * DRMAX
              RZINEW = RZIOLD + ( 2.0 * ZBQLU01(DUMM) - 1.0 ) * DRMAX

!          ** CALCULATE THE ENERGY OF I IN THE NEW CONFIGURATION **

              CALL ENERGY(RXINEW,RYINEW,RZINEW,I,SIGMA,VNEW,WNEW)

!          ** CHECK FOR ACCEPTANCE **

              DELTV  = VNEW - VOLD
              DELTW  = WNEW - WOLD
              DELTVB = BETA * DELTV

              IF ( DELTV .LE. 0.0 ) THEN
                    V      = V + DELTV
                    W      = W + DELTW
                    RX(I)  = RXINEW
                    RY(I)  = RYINEW
                    RZ(I)  = RZINEW
                    ACATMA = ACATMA + 1.0
                 ELSEIF ( EXP ( - DELTVB ) .GT. ZBQLU01(DUMM) ) THEN
                    V      = V + DELTV
                    W      = W + DELTW
                    RX(I)  = RXINEW
                    RY(I)  = RYINEW
                    RZ(I)  = RZINEW
                    ACATMA = ACATMA + 1.0
               ENDIF

               ACM = ACM + 1.0
               
!          ** CALCULATE INSTANTANEOUS VALUES **

	      VN     = ( V ) / REAL ( N )
              PRES   = DENS * TEMP + W

!          ** CONVERT PRESSURE TO LJ UNITS **

              PRES   = PRES * SIGMA ** 3

!          ** ACCUMULATE AVERAGES **

              IF (STEP.GT.NEQU) THEN
                 ACM1   = ACM1  + 1.0
                 ACV    = ACV   + VN
                 ACP    = ACP   + PRES
                 ACVSQ  = ACVSQ + VN * VN
                 ACPSQ  = ACPSQ + PRES * PRES
              ENDIF

!          *************************************************************
!          ** ENDS LOOP OVER ATOMS                                    **
!          *************************************************************

           ENDDO

!      ** CALCULATE ORDER PARAMETER **

           CALL ORDER ( KLATX, KLATY, KLATZ, PARAM )
           IF (STEP.GT.NEQU) THEN
              AVPARA=AVPARA+PARAM
              AVPASQ=AVPASQ+PARAM*PARAM
              NPARAM=NPARAM+1
           ENDIF

!       ** PERFORM PERIODIC OPERATIONS  **

           IF ( MOD ( STEP, IPRINT ) .EQ. 0 ) THEN
!          ** WRITE OUT RUNTIME INFORMATION **
              WRITE(*,'(2I8,4F12.6)') STEP, INT(ACM), RATIO, VN, PRES, PARAM
           ENDIF
           IF ( MOD ( STEP, ISAVE ) .EQ. 0 ) THEN
!          ** WRITE OUT THE CONFIGURATION AT INTERVALS **
              CALL WRITCN ( CNFILE )
           ENDIF

        ENDDO

        WRITE(6,'(20X,''EQUILIBRATION FINISHED '',I10)')
   
!    *******************************************************************
!    ** SIMULATED ANNEALING STARTED                                   **
!    *******************************************************************
	
	TCACC = 0
	TCATM = 0

        DO WHILE ( TEMP .GT. 0.039777 )	
	
	   STEP = STEP+1

           DO I = 1, N
	   
	      TCATM = TCATM + 1	

              RXIOLD = RX(I)
              RYIOLD = RY(I)
              RZIOLD = RZ(I)

!          ** CALCULATE THE ENERGY OF I IN THE OLD CONFIGURATION **

              CALL ENERGY(RXIOLD,RYIOLD,RZIOLD,I,SIGMA,VOLD,WOLD)

!          ** MOVE I AND PICKUP THE CENTRAL IMAGE **

              RXINEW = RXIOLD + ( 2.0 * ZBQLU01(DUMM) - 1.0 ) * DRMAX
              RYINEW = RYIOLD + ( 2.0 * ZBQLU01(DUMM) - 1.0 ) * DRMAX
              RZINEW = RZIOLD + ( 2.0 * ZBQLU01(DUMM) - 1.0 ) * DRMAX

!          ** CALCULATE THE ENERGY OF I IN THE NEW CONFIGURATION **

              CALL ENERGY(RXINEW,RYINEW,RZINEW,I,SIGMA,VNEW,WNEW)

!          ** CHECK FOR ACCEPTANCE **

              DELTV  = VNEW - VOLD
              DELTW  = WNEW - WOLD
              DELTVB = BETA * DELTV

              IF ( DELTV .LE. 0.0 ) THEN
                    V      = V + DELTV
                    W      = W + DELTW
                    RX(I)  = RXINEW
                    RY(I)  = RYINEW
                    RZ(I)  = RZINEW
                    ACATMA = ACATMA + 1.0
		    TCACC = TCACC + 1
                 ELSEIF ( EXP ( - DELTVB ) .GT. ZBQLU01(DUMM) ) THEN
                    V      = V + DELTV
                    W      = W + DELTW
                    RX(I)  = RXINEW
                    RY(I)  = RYINEW
                    RZ(I)  = RZINEW
                    ACATMA = ACATMA + 1.0
		    TCACC = TCACC + 1
               ENDIF

                ACM = ACM + 1.0
               
!          ** CALCULATE INSTANTANEOUS VALUES **

	      VN     = ( V ) / REAL ( N )
              PRES   = DENS * TEMP + W

!          ** CONVERT PRESSURE TO LJ UNITS **

              PRES   = PRES * SIGMA ** 3

!          ** ACCUMULATE AVERAGES **

              IF (STEP.GT.NEQU) THEN
                 ACM1   = ACM1  + 1.0
                 ACV    = ACV   + VN
                 ACP    = ACP   + PRES
                 ACVSQ  = ACVSQ + VN * VN
                 ACPSQ  = ACPSQ + PRES * PRES
              ENDIF

!          *************************************************************
!          ** ENDS LOOP OVER ATOMS                                    **
!          *************************************************************

           ENDDO

!      ** CALCULATE ORDER PARAMETER **

           CALL ORDER ( KLATX, KLATY, KLATZ, PARAM )
           IF (STEP.GT.NEQU) THEN
              AVPARA=AVPARA+PARAM
              AVPASQ=AVPASQ+PARAM*PARAM
              NPARAM=NPARAM+1
           ENDIF

!       ** PERFORM PERIODIC OPERATIONS  **

           IF ( MOD ( STEP, IPRINT ) .EQ. 0 ) THEN
!          ** WRITE OUT RUNTIME INFORMATION **
              WRITE(*,'(2I8,4F12.6)') STEP, INT(ACM), RATIO, VN, PRES, TEMP
           ENDIF
           IF ( MOD ( STEP, ISAVE ) .EQ. 0 ) THEN
!          ** WRITE OUT THE CONFIGURATION AT INTERVALS **
              CALL WRITCN ( CNFILE )
           ENDIF

	   IF ( TCACC .GT. 10000) THEN
!	   ** SET NEW TEMPERATURE AND RESET TCACC, TCATM **
		TCACC = 0
		TCATM = 0
		TEMP = TEMP*0.999
		BETA = BETA / 0.999
	   ENDIF
	   IF ( TCATM .EQ. 50000) THEN
!	   ** SET NEW TEMPERATURE AND RESET TCACC, TCATM **
		TCACC = 0
		TCATM = 0
		TEMP = TEMP*0.999
		BETA = BETA / 0.999
	   ENDIF
	   	
!    *******************************************************************
!    ** ENDS THE LOOP OVER CYCLES                                     **
!    *******************************************************************

        ENDDO     	  	   
        
	WRITE(*,'(//'' END OF SIMULATED ANNEALING         ''//)')

!    ** CHECKS FINAL VALUE OF THE POTENTIAL ENERGY IS CONSISTENT **

        CALL SUMUP ( RMIN, SIGMA, OVRLAP, VEND, WEND )

        IF ( ABS ( VEND - V ) .GT. 1.0E-03 ) THEN

           WRITE(*,'('' PROBLEM WITH ENERGY,'')')
           WRITE(*,'('' VEND              = '', E20.6)') VEND
           WRITE(*,'('' V                 = '', E20.6)') V

        ENDIF

!    ** WRITE OUT THE FINAL CONFIGURATION FROM THE RUN **

        CALL WRITCN ( CNFILE )

	CLOSE ( UNIT = 11 )

!    ** CALCULATE AND WRITE OUT RUNNING AVERAGES **

        AVV    = ACV / ACM1
        ACVSQ  = ( ACVSQ / ACM1 ) - AVV ** 2
        AVP    = ACP / ACM1
        ACPSQ  = ( ACPSQ / ACM1 ) - AVP ** 2
        AVPARA = AVPARA/NPARAM
        AVPASQ = (AVPASQ/NPARAM) - AVPARA**2

!    ** CALCULATE FLUCTUATIONS **

        IF ( ACVSQ .GT. 0.0 ) FLV = SQRT ( ACVSQ )
        IF ( ACPSQ .GT. 0.0 ) FLP = SQRT ( ACPSQ )
        IF ( NPARAM .GT. 0.0 ) FPAR = SQRT ( AVPASQ )

        WRITE(*,'(/'' AVERAGES ''/ )')
        WRITE(*,'('' <V/N>   = '',F10.6)') AVV
        WRITE(*,'('' <P>     = '',F10.6)') AVP

        WRITE(*,'('' ORDER PARAMETER = '',F10.6)') AVPARA

        WRITE(*,'(/'' FLUCTUATIONS ''/)')

        WRITE(*,'('' FLUCTUATION IN <V/N>      = '',F10.6)') FLV
        WRITE(*,'('' FLUCTUATION IN <P>        = '',F10.6)') FLP
        WRITE(*,'('' FLUCTUATION IN <ORDERP>   = '',F10.6)') FPAR
        WRITE(*,'(/'' END OF SIMULATION '')')

        STOP
        END



        SUBROUTINE SUMUP ( RMIN, SIGMA, OVRLAP, V, W )


!    *******************************************************************
!    ** CALCULATES THE TOTAL POTENTIAL ENERGY FOR A CONFIGURATION.    **
!    **                                                               **
!    ** PRINCIPAL VARIABLES:                                          **
!    **                                                               **
!    ** INTEGER N                 THE NUMBER OF ATOMS                 **
!    ** REAL    RX(N(,RY(N),RZ(N) THE POSITIONS OF THE ATOMS          **
!    ** REAL    V                 THE POTENTIAL ENERGY                **
!    ** REAL    W                 THE VIRIAL                          **
!    ** LOGICAL OVRLAP            TRUE FOR SUBSTANTIAL ATOM OVERLAP   **
!    **                                                               **
!    ** USAGE:                                                        **
!    **                                                               **
!    ** THE SUBROUTINE RETURNS THE TOTAL POTENTIAL ENERGY AT THE      **
!    ** BEGINNING AND END OF THE RUN.                                 **
!    *******************************************************************

        include 'common.f'

        REAL*8        SIGMA, RMIN, V, W
        LOGICAL     OVRLAP

        REAL*8        RMINSQ, SIGSQ, RXIJ, RYIJ, RZIJ
        REAL*8        RXI, RYI, RZI, VIJ, WIJ, SR2, SR6, RIJSQ
        INTEGER     I, J

!    *******************************************************************

        OVRLAP = .FALSE.
        RMINSQ = RMIN * RMIN
        SIGSQ  = SIGMA * SIGMA

        V      = 0.0
        W      = 0.0

!    ** LOOP OVER ALL THE PAIRS IN THE LIQUID **

        DO I = 1, N - 1
           RXI = RX(I)
           RYI = RY(I)
           RZI = RZ(I)
           DO J = I + 1, N
              RXIJ  = RXI - RX(J)
              RYIJ  = RYI - RY(J)
              RZIJ  = RZI - RZ(J)
              RIJSQ = RXIJ * RXIJ + RYIJ * RYIJ + RZIJ * RZIJ
              IF ( RIJSQ .LT. RMINSQ ) THEN
                 OVRLAP = .TRUE.
                 RETURN
              ELSE
                 SR2 = SIGSQ / RIJSQ
                 SR6 = SR2 * SR2 * SR2
                 VIJ = SR6 * ( SR6 - 1.0 )
                 WIJ = SR6 * ( SR6 - 0.5 )
                 V   = V + VIJ
                 W   = W + WIJ
              ENDIF
           ENDDO
        ENDDO

        V = 4.0 * V
        W = 48.0 * W / 3.0

        RETURN
        END



        SUBROUTINE ENERGY ( RXI, RYI, RZI, I, SIGMA, V, W )


!    *******************************************************************
!    ** RETURNS THE POTENTIAL ENERGY OF ATOM I WITH ALL OTHER ATOMS.  **
!    **                                                               **
!    ** PRINCIPAL VARIABLES:                                          **
!    **                                                               **
!    ** INTEGER I                 THE ATOM OF INTEREST                **
!    ** INTEGER N                 THE NUMBER OF ATOMS                 **
!    ** REAL    RX(N),RY(N),RZ(N) THE ATOM POSITIONS                  **
!    ** REAL    RXI,RYI,RZI       THE COORDINATES OF ATOM I           **
!    ** REAL    V                 THE POTENTIAL ENERGY OF ATOM I      **
!    ** REAL    W                 THE VIRIAL OF ATOM I                **
!    **                                                               **
!    ** USAGE:                                                        **
!    **                                                               **
!    ** THIS SUBROUTINE IS USED TO CALCULATE THE CHANGE OF ENERGY     **
!    ** DURING A TRIAL MOVE OF ATOM I. IT IS CALLED BEFORE AND        **
!    ** AFTER THE RANDOM DISPLACEMENT OF I.                           **
!    *******************************************************************

        include 'common.f'

        REAL*8        SIGMA, RXI, RYI, RZI, V, W
        INTEGER     I

        REAL*8        SIGSQ, SR2, SR6
        REAL*8        RXIJ, RYIJ, RZIJ, RIJSQ, VIJ, WIJ
        INTEGER     J

!     ******************************************************************

        SIGSQ  = SIGMA * SIGMA

        V      = 0.0
        W      = 0.0

!    ** LOOP OVER ALL MOLECULES EXCEPT I  **

        DO J = 1, N
           IF ( I .NE. J ) THEN
              RXIJ  = RXI - RX(J)
              RYIJ  = RYI - RY(J)
              RZIJ  = RZI - RZ(J)
              RIJSQ = RXIJ * RXIJ + RYIJ * RYIJ + RZIJ * RZIJ
	   
                 SR2 = SIGSQ / RIJSQ
                 SR6 = SR2 * SR2 * SR2
                 VIJ = SR6 * ( SR6 - 1.0 )
                 WIJ = SR6 * ( SR6 - 0.5 )
                 V   = V + VIJ
                 W   = W + WIJ

           ENDIF
        ENDDO

        V = 4.0 * V
        W = 48.0 * W / 3.0

        RETURN
        END
        
        
!	RANDOM NUMBER GENERATOR

! *******************************************************************
! ********	FILE: randgen.f				***********
! ********	AUTHORS: Richard Chandler		***********
! ********		 (richard@stats.ucl.ac.uk)	***********
! ********		 Paul Northrop 			***********
! ********		 (northrop@stats.ox.ac.uk)	***********
! ********	LAST MODIFIED: 26/8/03			***********
! ********	See file randgen.txt for details	***********
! *******************************************************************

      BLOCK DATA ZBQLBD01

!*       Initializes seed array etc. for random number generator.
!*       The values below have themselves been generated using the
!*       NAG generator.

      COMMON /ZBQL0001/ ZBQLIX,B,C
      DOUBLE PRECISION ZBQLIX(43),B,C
      INTEGER I
      DATA (ZBQLIX(I),I=1,43) /8.001441D7,5.5321801D8,&
     &1.69570999D8,2.88589940D8,2.91581871D8,1.03842493D8,&
     &7.9952507D7,3.81202335D8,3.11575334D8,4.02878631D8,&
     &2.49757109D8,1.15192595D8,2.10629619D8,3.99952890D8,&
     &4.12280521D8,1.33873288D8,7.1345525D7,2.23467704D8,&
     &2.82934796D8,9.9756750D7,1.68564303D8,2.86817366D8,&
     &1.14310713D8,3.47045253D8,9.3762426D7 ,1.09670477D8,&
     &3.20029657D8,3.26369301D8,9.441177D6,3.53244738D8,&
     &2.44771580D8,1.59804337D8,2.07319904D8,3.37342907D8,&
     &3.75423178D8,7.0893571D7 ,4.26059785D8,3.95854390D8,&
     &2.0081010D7,5.9250059D7,1.62176640D8,3.20429173D8,&
     &2.63576576D8/
      DATA B / 4.294967291D9 /
      DATA C / 0.0D0 /
      END
!******************************************************************
!******************************************************************
!******************************************************************
      SUBROUTINE ZBQLINI(SEED)
!******************************************************************
!*       To initialize the random number generator - either
!*       repeatably or nonrepeatably. Need double precision
!*       variables because integer storage can't handle the
!*       numbers involved
!******************************************************************
!*	ARGUMENTS
!*	=========
!*	SEED	(integer, input). User-input number which generates
!*		elements of the array ZBQLIX, which is subsequently used 
!*		in the random number generation algorithm. If SEED=0,
!*		the array is seeded using the system clock if the 
!*		FORTRAN implementation allows it.
!******************************************************************
!*	PARAMETERS
!*	==========
!*	LFLNO	(integer). Number of lowest file handle to try when
!*		opening a temporary file to copy the system clock into.
!*		Default is 80 to keep out of the way of any existing
!*		open files (although the program keeps searching till
!*		it finds an available handle). If this causes problems,
!*               (which will only happen if handles 80 through 99 are 
!*               already in use), decrease the default value.
!******************************************************************
      INTEGER LFLNO
      PARAMETER (LFLNO=80)
!******************************************************************
!*	VARIABLES
!*	=========
!*	SEED	See above
!*	ZBQLIX	Seed array for the random number generator. Defined
!*		in ZBQLBD01
!*	B,C	Used in congruential initialisation of ZBQLIX
!*	SS,MM,}	System clock secs, mins, hours and days
!*	HH,DD }
!*	FILNO	File handle used for temporary file
!*	INIT	Indicates whether generator has already been initialised

      INTEGER SEED,SS,MM,HH,DD,FILNO,I
      INTEGER INIT
      DOUBLE PRECISION ZBQLIX(43),B,C
      DOUBLE PRECISION TMPVAR1,DSS,DMM,DHH,DDD

      COMMON /ZBQL0001/ ZBQLIX,B,C
      SAVE INIT

!*	Ensure we don't call this more than once in a program

      IF (INIT.GE.1) THEN
       IF(INIT.EQ.1) THEN
        WRITE(*,1)
        INIT = 2
       ENDIF
       RETURN
      ELSE
       INIT = 1
      ENDIF

!*       If SEED = 0, cat the contents of the clock into a file
!*       and transform to obtain ZQBLIX(1), then use a congr.
!*       algorithm to set remaining elements. Otherwise take
!*       specified value of SEED.

!*>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
!*>>>>>>>	NB FOR SYSTEMS WHICH DO NOT SUPPORT THE  >>>>>>>
!*>>>>>>>	(NON-STANDARD) 'CALL SYSTEM' COMMAND,    >>>>>>>
!*>>>>>>>	THIS WILL NOT WORK, AND THE FIRST CLAUSE >>>>>>>
!*>>>>>>>	OF THE FOLLOWING IF BLOCK SHOULD BE	 >>>>>>>
!*>>>>>>>	COMMENTED OUT.				 >>>>>>>
!*>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
      IF (SEED.EQ.0) THEN
!*>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
!*>>>>>>>	COMMENT OUT FROM HERE IF YOU DON'T HAVE  >>>>>>>
!*>>>>>>>	'CALL SYSTEM' CAPABILITY ...		 >>>>>>>
!*>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
       CALL SYSTEM(' date +%S%M%H%j > zbql1234.tmp')

!*       Try all file numbers for LFLNO to 999 

       FILNO = LFLNO
 10    OPEN(FILNO,FILE='zbql1234.tmp',ERR=11)
       GOTO 12
 11    FILNO = FILNO + 1
       IF (FILNO.GT.999) THEN
        WRITE(*,2)
        RETURN
       ENDIF
       GOTO 10
 12    READ(FILNO,'(3(I2),I3)') SS,MM,HH,DD
       CLOSE(FILNO)
       CALL SYSTEM('rm zbql1234.tmp')
       DSS = DINT((DBLE(SS)/6.0D1) * B)
       DMM = DINT((DBLE(MM)/6.0D1) * B)
       DHH = DINT((DBLE(HH)/2.4D1) * B)
       DDD = DINT((DBLE(DD)/3.65D2) * B)
       TMPVAR1 = DMOD(DSS+DMM+DHH+DDD,B)

!<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
!<<<<<<<<	... TO HERE (END OF COMMENTING OUT FOR 	  <<<<<<<
!<<<<<<<<	USERS WITHOUT 'CALL SYSTEM' CAPABILITY	  <<<<<<<
!<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

      ELSE
       TMPVAR1 = DMOD(DBLE(SEED),B)
      ENDIF
      ZBQLIX(1) = TMPVAR1
      DO 100 I = 2,43
       TMPVAR1 = ZBQLIX(I-1)*3.0269D4
       TMPVAR1 = DMOD(TMPVAR1,B)       
       ZBQLIX(I) = TMPVAR1
 100  CONTINUE

 1    FORMAT(//5X,'****WARNING**** You have called routine ZBQLINI ',&
     &'more than',/5X,'once. I''m ignoring any subsequent calls.',//)
 2    FORMAT(//5X,'**** ERROR **** In routine ZBQLINI, I couldn''t',&
     &' find an',/5X,&
     &'available file number. To rectify the problem, decrease the ',&
     &'value of',/5X,&
     &'the parameter LFLNO at the start of this routine (in file ',&
     &'randgen.f)',/5X,&
     &'and recompile. Any number less than 100 should work.')
      END
      
!*****************************************************************
      REAL*8 FUNCTION ZBQLU01(DUMMY)

!*       Returns a uniform random number between 0 & 1, using
!*       a Marsaglia-Zaman type subtract-with-borrow generator.
!*       Uses double precision, rather than integer, arithmetic 
!*       throughout because MZ's integer constants overflow
!*       32-bit integer storage (which goes from -2^31 to 2^31).
!*       Ideally, we would explicitly truncate all integer 
!*       quantities at each stage to ensure that the double
!*       precision representations do not accumulate approximation
!*       error; however, on some machines the use of DNINT to
!*       accomplish this is *seriously* slow (run-time increased
!*       by a factor of about 3). This double precision version 
!*       has been tested against an integer implementation that
!*       uses long integers (non-standard and, again, slow) -
!*       the output was identical up to the 16th decimal place
!*       after 10^10 calls, so we're probably OK ...

	REAL*8 DUMMY
      DOUBLE PRECISION B,C,ZBQLIX(43),X,B2,BINV
      INTEGER CURPOS,ID22,ID43

      COMMON /ZBQL0001/ ZBQLIX,B,C
      SAVE /ZBQL0001/
      SAVE CURPOS,ID22,ID43
      DATA CURPOS,ID22,ID43 /1,22,43/

      B2 = B
      BINV = 1.0D0/B
 5    X = ZBQLIX(ID22) - ZBQLIX(ID43) - C
      IF (X.LT.0.0D0) THEN
       X = X + B
       C = 1.0D0
      ELSE
       C = 0.0D0
      ENDIF
      ZBQLIX(ID43) = X

!*     Update array pointers. Do explicit check for bounds of each to
!*     avoid expense of modular arithmetic. If one of them is 0 the others
!*     won't be

      CURPOS = CURPOS - 1
      ID22 = ID22 - 1
      ID43 = ID43 - 1
      IF (CURPOS.EQ.0) THEN
       CURPOS=43
      ELSEIF (ID22.EQ.0) THEN
       ID22 = 43
      ELSEIF (ID43.EQ.0) THEN
       ID43 = 43
      ENDIF

!*     The integer arithmetic there can yield X=0, which can cause 
!*     problems in subsequent routines (e.g. ZBQLEXP). The problem
!*     is simply that X is discrete whereas U is supposed to 
!*     be continuous - hence if X is 0, go back and generate another
!*     X and return X/B^2 (etc.), which will be uniform on (0,1/B). 

      IF (X.LT.BINV) THEN
       B2 = B2*B
       GOTO 5
      ENDIF

      ZBQLU01 = X/B2

      END

!***********************************************************************

        SUBROUTINE READCN ( CNFILE )


!    *******************************************************************
!    ** SUBROUTINE TO READ IN THE CONFIGURATION FROM UNIT 10          **
!    *******************************************************************

        include 'common.f'

        CHARACTER   CNFILE*(*)
        INTEGER     CNUNIT
        PARAMETER ( CNUNIT = 10 )

        INTEGER     I

!   ********************************************************************

        OPEN ( UNIT = CNUNIT, FILE = CNFILE, STATUS = 'OLD')


        READ ( CNUNIT,* ) N
        IF ( N .GT. NMAX ) STOP 'N ERROR IN READCN'
        DO I=1,N
           READ ( CNUNIT,* ) RX(I), RY(I), RZ(I)
        ENDDO

        CLOSE ( UNIT = CNUNIT )

        RETURN
        END



        SUBROUTINE WRITCN ( CNFILE )


!    *******************************************************************
!    ** SUBROUTINE TO WRITE OUT THE CONFIGURATION TO UNIT 10          **
!    *******************************************************************

        include 'common.f'

        CHARACTER   CNFILE*(*)
        INTEGER     CNUNIT
        PARAMETER ( CNUNIT = 11 )
        INTEGER I

!   ********************************************************************

  !      OPEN ( UNIT = CNUNIT, FILE = 'conf.xyz', STATUS = 'UNKNOWN' )


        WRITE ( CNUNIT,* ) N
	WRITE ( CNUNIT,* ) 'Temp ',TEMP
        DO I=1,N
           WRITE ( CNUNIT,* ) 'Ar ', RX(I), RY(I), RZ(I)
        ENDDO

 !       CLOSE ( UNIT = CNUNIT )

        RETURN
        END



! ********************************************************************************
! ** FICHE F.25.  ROUTINE TO CALCULATE TRANSLATIONAL ORDER PARAMETER            **
! ** This FORTRAN code is intended to illustrate points made in the text.       **
! ** To our knowledge it works correctly.  However it is the responsibility of  **
! ** the user to test it, if it is to be used in a research application.        **
! ********************************************************************************



        SUBROUTINE ORDER ( KLATX, KLATY, KLATZ, PARAM )


!    *******************************************************************
!    ** CALCULATION OF TRANSLATIONAL ORDER PARAMETER (MELTING FACTOR).**
!    **                                                               **
!    ** CLASSICALLY, THE ORDER PARAMETER IS A NORMALIZED SUM OF       **
!    ** COSINE TERMS WHICH SHOULD BE UNITY IN THE PERFECT LATTICE     **
!    ** AND FLUCTUATE AROUND ZERO FOR A DISORDERED SYSTEM.            **
!    ** HOWEVER, THIS IS NOT ORIGIN-INDEPENDENT: WITH AN UNSUITABLE   **
!    ** CHOICE OF ORIGIN IT COULD VANISH EVEN IN A PERFECT LATTICE.   **
!    ** ACCORDINGLY, WE CALCULATE HERE A QUANTITY THAT IS INDEPENDENT **
!    ** OF THE ORIGIN OF COORDINATES.                                 **
!    ** IT SHOULD BE UNITY IN A LATTICE FOR WHICH A RECIPROCAL VECTOR **
!    ** (KLATX,KLATY,KLATZ) IS SUPPLIED.                              **
!    ** IT SHOULD BE POSITIVE BUT SMALL, OF ORDER SQRT(N) IN A        **
!    ** DISORDERED SYSTEM.                                            **
!    **                                                               **
!    ** PRINCIPAL VARIABLES:                                          **
!    **                                                               **
!    ** INTEGER N                 NUMBER OF MOLECULES                 **
!    ** REAL    RX(N),RY(N),RZ(N) MOLECULAR COORDINATES               **
!    ** REAL    KLATX,KLATY,KLATZ RECIPROC. VECTOR OF INITIAL LATTICE **
!    ** REAL    PARAM             RESULT: ORDER PARAMETER             **
!    *******************************************************************

        include 'common.f'

        REAL*8        KLATX, KLATY, KLATZ, PARAM

        INTEGER     I
        REAL*8        SINSUM, COSSUM

!    *******************************************************************

        SINSUM = 0.0
        COSSUM = 0.0

        DO I = 1, N
           COSSUM = COSSUM + COS(KLATX*RX(I)+KLATY*RY(I)+KLATZ*RZ(I))
           SINSUM = SINSUM + SIN(KLATX*RX(I)+KLATY*RY(I)+KLATZ*RZ(I) )
        ENDDO

        COSSUM = COSSUM / REAL ( N )
        SINSUM = SINSUM / REAL ( N )
        PARAM  = SQRT ( COSSUM ** 2 + SINSUM ** 2 )

        RETURN
        END



