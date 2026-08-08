using LifeMate.Domain.Common;

namespace LifeMate.Domain.People;

public enum PersonStatus
{
    Active,
    Deceased,
    Deleted
}

public enum PersonSubjectCategory
{
    Adult,
    Child,
    Dependent
}

/// <summary>
/// Real data subject. A Person can exist without any Account.
/// </summary>
public sealed class Person
{
    private Person() { }

    public Person(Guid id, PersonSubjectCategory subjectCategory, DateTime utcNow)
    {
        if (id == Guid.Empty) throw new DomainException("Person id is required.");
        Id = id;
        SubjectCategory = subjectCategory;
        Status = PersonStatus.Active;
        CreatedAtUtc = EnsureUtc(utcNow);
        UpdatedAtUtc = CreatedAtUtc;
    }

    public Guid Id { get; private set; }
    public PersonSubjectCategory SubjectCategory { get; private set; }
    public PersonStatus Status { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime UpdatedAtUtc { get; private set; }

    public void MarkDeleted(DateTime utcNow)
    {
        Status = PersonStatus.Deleted;
        UpdatedAtUtc = EnsureUtc(utcNow);
    }

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}
