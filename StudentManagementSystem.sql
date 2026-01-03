
/*
Student Management System (SQL Server T-SQL)

Includes:
 - Database creation
 - Tables (DDL)
 - Indexes
 - UDFs, Stored Procedures
 - Triggers (audit)
 - Sample data (DML)
 - Simple unit tests (validation queries & procedure calls)
Notes:
 - Run on SQL Server Management Studio (SSMS) or Azure Data Studio.
 - Adjust file paths/permissions as required.
*/

-- 1. Create database and use it
CREATE DATABASE StudentDB;
GO
USE StudentDB;
GO

-- 2. Tables (DDL)
CREATE TABLE Students (
    StudentID INT IDENTITY(1000,1) PRIMARY KEY,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    DOB DATE NULL,
    Email VARCHAR(100) NULL UNIQUE,
    Phone CHAR(10) NULL,
    Gender CHAR(1) NULL CHECK (Gender IN ('M','F','O')),
    AdmissionDate DATETIME DEFAULT SYSUTCDATETIME(),
    IsActive BIT DEFAULT 1
);
GO

CREATE TABLE Courses (
    CourseID INT IDENTITY(100,1) PRIMARY KEY,
    CourseName VARCHAR(150) NOT NULL,
    Code VARCHAR(20) NULL UNIQUE,
    Credits TINYINT NOT NULL CHECK (Credits BETWEEN 1 AND 10),
    Description VARCHAR(500) NULL
);
GO

CREATE TABLE Faculty (
    FacultyID INT IDENTITY(200,1) PRIMARY KEY,
    FullName VARCHAR(150) NOT NULL,
    Department VARCHAR(100) NULL,
    Email VARCHAR(100) NULL UNIQUE,
    Salary DECIMAL(12,2) NULL CHECK (Salary >= 0),
    HireDate DATE NULL
);
GO

CREATE TABLE Enrollments (
    EnrollID INT IDENTITY(10000,1) PRIMARY KEY,
    StudentID INT NOT NULL,
    CourseID INT NOT NULL,
    EnrollDate DATETIME DEFAULT SYSUTCDATETIME(),
    Status VARCHAR(20) DEFAULT 'Enrolled',
    CONSTRAINT FK_Enroll_Student FOREIGN KEY (StudentID) REFERENCES Students(StudentID) ON DELETE CASCADE,
    CONSTRAINT FK_Enroll_Course FOREIGN KEY (CourseID) REFERENCES Courses(CourseID) ON DELETE CASCADE,
    CONSTRAINT UQ_Student_Course UNIQUE (StudentID, CourseID)
);
GO

CREATE TABLE Payments (
    PaymentID INT IDENTITY(50000,1) PRIMARY KEY,
    StudentID INT NOT NULL,
    Amount DECIMAL(10,2) NOT NULL CHECK (Amount >= 0),
    PaymentDate DATETIME DEFAULT SYSUTCDATETIME(),
    Mode VARCHAR(50) DEFAULT 'Bank Transfer',
    ReferenceNo VARCHAR(100) NULL,
    CONSTRAINT FK_Payment_Student FOREIGN KEY (StudentID) REFERENCES Students(StudentID) ON DELETE CASCADE
);
GO

CREATE TABLE StudentAudit (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    StudentID INT NOT NULL,
    ChangeType VARCHAR(20) NOT NULL, -- INSERT, UPDATE, DELETE
    ChangedField VARCHAR(100) NULL,
    OldValue VARCHAR(500) NULL,
    NewValue VARCHAR(500) NULL,
    ChangedBy VARCHAR(100) NULL,
    ChangedDate DATETIME DEFAULT SYSUTCDATETIME()
);
GO

-- 3. Indexes

CREATE NONCLUSTERED INDEX IX_Students_Email ON Students(Email);
CREATE NONCLUSTERED INDEX IX_Enrollments_Student ON Enrollments(StudentID);
CREATE NONCLUSTERED INDEX IX_Enrollments_Course ON Enrollments(CourseID);
CREATE NONCLUSTERED INDEX IX_Payments_StudentDate ON Payments(StudentID, PaymentDate);
GO

-- 4. UDFs

CREATE FUNCTION dbo.GetFullName(@StudentID INT)
RETURNS VARCHAR(200)
AS
BEGIN
    DECLARE @FullName VARCHAR(200);
    SELECT @FullName = CONCAT(FirstName, ' ', LastName)
    FROM Students WHERE StudentID = @StudentID;
    RETURN ISNULL(@FullName, '');
END;
GO

-- 5. Stored Procedures

CREATE PROCEDURE dbo.AddStudent
    @FirstName VARCHAR(50),
    @LastName VARCHAR(50),
    @DOB DATE = NULL,
    @Email VARCHAR(100) = NULL,
    @Phone CHAR(10) = NULL,
    @Gender CHAR(1) = NULL,
    @NewStudentID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Students (FirstName, LastName, DOB, Email, Phone, Gender)
    VALUES (@FirstName, @LastName, @DOB, @Email, @Phone, @Gender);

    SET @NewStudentID = SCOPE_IDENTITY();
END;
GO


CREATE PROCEDURE dbo.EnrollStudent
    @StudentID INT,
    @CourseID INT,
    @EnrollID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- Simple check to ensure student and course exist
    IF NOT EXISTS (SELECT 1 FROM Students WHERE StudentID = @StudentID)
    BEGIN
        RAISERROR('StudentID %d does not exist.', 16, 1, @StudentID);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Courses WHERE CourseID = @CourseID)
    BEGIN
        RAISERROR('CourseID %d does not exist.', 16, 1, @CourseID);
        RETURN;
    END

    BEGIN TRY
        INSERT INTO Enrollments (StudentID, CourseID) VALUES (@StudentID, @CourseID);
        SET @EnrollID = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR('Enrollment failed: %s', 16, 1, @ErrMsg);
    END CATCH
END;
GO


CREATE PROCEDURE dbo.AddPayment
    @StudentID INT,
    @Amount DECIMAL(10,2),
    @Mode VARCHAR(50) = 'Bank Transfer',
    @ReferenceNo VARCHAR(100) = NULL,
    @PaymentID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Students WHERE StudentID = @StudentID)
    BEGIN
        RAISERROR('StudentID %d does not exist.', 16, 1, @StudentID);
        RETURN;
    END

    INSERT INTO Payments (StudentID, Amount, Mode, ReferenceNo)
    VALUES (@StudentID, @Amount, @Mode, @ReferenceNo);

    SET @PaymentID = SCOPE_IDENTITY();
END;
GO


-- 6. Trigger: Audit Student changes (INSERT/UPDATE/DELETE)

CREATE TRIGGER trg_AuditStudentChanges
ON Students
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- INSERT
    IF EXISTS(SELECT 1 FROM inserted) AND NOT EXISTS(SELECT 1 FROM deleted)
    BEGIN
        INSERT INTO StudentAudit(StudentID, ChangeType, ChangedDate)
        SELECT i.StudentID, 'INSERT', SYSUTCDATETIME()
        FROM inserted i;
    END

    -- DELETE
    IF EXISTS(SELECT 1 FROM deleted) AND NOT EXISTS(SELECT 1 FROM inserted)
    BEGIN
        INSERT INTO StudentAudit(StudentID, ChangeType, ChangedDate)
        SELECT d.StudentID, 'DELETE', SYSUTCDATETIME()
        FROM deleted d;
    END

    -- UPDATE (log changed columns - currently logs Email changes only; extend as needed)
    IF EXISTS(SELECT 1 FROM inserted) AND EXISTS(SELECT 1 FROM deleted)
    BEGIN
        INSERT INTO StudentAudit(StudentID, ChangeType, ChangedField, OldValue, NewValue, ChangedDate)
        SELECT d.StudentID, 'UPDATE', 'Email', d.Email, i.Email, SYSUTCDATETIME()
        FROM deleted d
        JOIN inserted i ON d.StudentID = i.StudentID
        WHERE ISNULL(d.Email,'') <> ISNULL(i.Email,'');

        -- Example for Phone
        INSERT INTO StudentAudit(StudentID, ChangeType, ChangedField, OldValue, NewValue, ChangedDate)
        SELECT d.StudentID, 'UPDATE', 'Phone', d.Phone, i.Phone, SYSUTCDATETIME()
        FROM deleted d
        JOIN inserted i ON d.StudentID = i.StudentID
        WHERE ISNULL(d.Phone,'') <> ISNULL(i.Phone,'');
    END
END;
GO

-- 7. Sample Data (DML)
SET NOCOUNT ON;

-- Students
INSERT INTO Students (FirstName, LastName, DOB, Email, Phone, Gender)
VALUES
('Asha','Patel','2003-08-14','asha.patel@example.com','9988776655','F'),
('Ravi','Kumar','2002-05-30','ravi.kumar@example.com','9876543210','M'),
('Meena','Iyer','2001-12-01','meena.iyer@example.com','9123456789','F');
GO
select * from Students


-- Courses
INSERT INTO Courses (CourseName, Code, Credits, Description)
VALUES
('Database Systems','DB101',4,'Introduction to relational databases and SQL'),
('Data Structures','CS102',3,'Arrays, lists, trees, graphs, algorithms'),
('Web Development','WD103',3,'HTML, CSS, JavaScript, Server-side basics');
GO

-- Faculty
INSERT INTO Faculty (FullName, Department, Email, Salary, HireDate)
VALUES
('Dr. Suresh Rao','Computer Science','suresh.rao@example.com',75000,'2019-07-01'),
('Ms. Anita Desai','Computer Science','anita.desai@example.com',45000,'2021-03-15');
GO


-- Get student ids
DECLARE @s1 INT = (SELECT TOP 1 StudentID FROM Students WHERE Email='asha.patel@example.com');
DECLARE @s2 INT = (SELECT TOP 1 StudentID FROM Students WHERE Email='ravi.kumar@example.com');
DECLARE @c1 INT = (SELECT TOP 1 CourseID FROM Courses WHERE Code='DB101');
DECLARE @c2 INT = (SELECT TOP 1 CourseID FROM Courses WHERE Code='CS102');

-- Enrollments (use existing StudentIDs & CourseIDs)
INSERT INTO Enrollments (StudentID, CourseID) VALUES (@s1, @c1), (@s2, @c1), (@s2, @c2);

-- Payments
INSERT INTO Payments (StudentID, Amount, Mode, ReferenceNo)
VALUES (@s1, 5000, 'Bank Transfer', 'TXN1001'),
       (@s2, 4500, 'Card', 'TXN1002');
GO

-- 8. Unit Tests & Validation Scripts
PRINT '--- UNIT TESTS START ---';

-- Test 1: Validate UDF GetFullName
PRINT 'Test 1: GetFullName for a known student';
DECLARE @s1 INT = (SELECT TOP 1 StudentID 
				   FROM Students 
				   WHERE Email='asha.patel@example.com');
SELECT dbo.GetFullName(@s1) AS FullNameFor_s1;
GO

-- Test 2: AddStudent procedure
PRINT 'Test 2: AddStudent procedure';
DECLARE @newID INT;
EXEC dbo.AddStudent
    @FirstName    = 'Test',
    @LastName     = 'Student',
    @DOB          = '2000-01-01',
    @Email        = 'test.student0@example.com',
    @Phone        = '9000000000',
    @Gender       = 'O',
    @NewStudentID = @newID OUTPUT;
PRINT 'New student created with ID:';
SELECT @newID AS NewStudentID,dbo.GetFullName(@newID) AS NewStudentFullName;
GO

-- Test 3: EnrollStudent procedure - positive case
PRINT 'Test 3: EnrollStudent procedure (positive)';
DECLARE @newID INT = (SELECT TOP 1 StudentID
					  FROM Students
					  WHERE Email = 'test.student@example.com');
DECLARE @c2 INT = (SELECT TOP 1 CourseID 
				   FROM Courses
				   WHERE Code = 'CS102');
DECLARE @enrollID INT;
EXEC dbo.EnrollStudent
    @StudentID = @newID,
    @CourseID  = @c2,
    @EnrollID  = @enrollID OUTPUT;
SELECT @enrollID AS NewEnrollID;
GO

-- Test 4: EnrollStudent procedure - duplicate enrollment should fail due to unique constraint
PRINT 'Test 4: EnrollStudent duplicate enrollment (expect error)';
BEGIN TRY
    DECLARE @dupEnroll INT;
	DECLARE @newID INT = (SELECT TOP 1 StudentID
					  FROM Students
					  WHERE Email = 'test.student@example.com');
	DECLARE @c2 INT = (SELECT TOP 1 CourseID 
					  FROM Courses
					  WHERE Code = 'CS102');
    EXEC dbo.EnrollStudent @StudentID=@newID, @CourseID=@c2, @EnrollID=@dupEnroll OUTPUT;
END TRY
BEGIN CATCH
    PRINT 'Expected error on duplicate enrollment:';
    PRINT ERROR_MESSAGE();
END CATCH;
GO

-- Test 5: AddPayment procedure
PRINT 'Test 5: AddPayment procedure';
DECLARE @payID INT;
DECLARE @newID INT = (SELECT TOP 1 StudentID
					  FROM Students
					  WHERE Email = 'test.student@example.com');
EXEC dbo.AddPayment @StudentID=@newID, @Amount=3000, @Mode='Cash', @ReferenceNo='TXN2001', 
					@PaymentID=@payID OUTPUT;
SELECT @payID AS NewPaymentID;
GO

-- Test 6: Trigger audit - update student email and phone, then check audit table
PRINT 'Test 6: Trigger audit - update student email/phone';
DECLARE @newID INT = (SELECT TOP 1 StudentID
					  FROM Students
					  WHERE Email = 'test.student@example.com');
UPDATE Students SET Email='test.student2@example.com', 
					Phone='9111111111' 
				WHERE StudentID=@newID;
SELECT * FROM StudentAudit WHERE StudentID=@newID ORDER BY ChangedDate DESC;
GO

-- Test 7: Reporting query - students with their courses
PRINT 'Test 7: Reporting - students with their courses';
SELECT s.StudentID, dbo.GetFullName(s.StudentID) AS FullName, 
	   c.CourseName, 
	   e.EnrollDate
FROM Students s
JOIN Enrollments e ON s.StudentID = e.StudentID
JOIN Courses c ON e.CourseID = c.CourseID
ORDER BY s.StudentID;
GO

-- Test 8: Payments summary
PRINT 'Test 8: Payments summary per student';
SELECT s.StudentID, dbo.GetFullName(s.StudentID) AS FullName, 
	   ISNULL(SUM(p.Amount),0) AS TotalPaid
FROM Students s
LEFT JOIN Payments p ON s.StudentID = p.StudentID
GROUP BY s.StudentID, s.FirstName, s.LastName
ORDER BY s.StudentID;
GO

PRINT '--- UNIT TESTS END ---';


